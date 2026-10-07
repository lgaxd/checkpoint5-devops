package br.com.fiap.dimdim;

import br.com.fiap.dimdim.repository.FazendaRepository;
import br.com.fiap.dimdim.repository.UsuarioRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.Base64;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class DimdimApplicationTests {

    @DynamicPropertySource
    static void jwtTestSecret(DynamicPropertyRegistry registry) {
        registry.add("jwt.secret", () -> Base64.getEncoder().encodeToString(new byte[32]));
    }

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private FazendaRepository fazendaRepository;

    @Autowired
    private UsuarioRepository usuarioRepository;

    @BeforeEach
    void cleanDatabase() {
        fazendaRepository.deleteAll();
        usuarioRepository.deleteAll();
    }

    @Test
    void userAndFarmSupportCompleteCrudAndRelationship() throws Exception {
        String token = register("owner@example.com");
        MvcResult createdUser = mockMvc.perform(post("/api/usuarios")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"nome":"Ana Silva","email":"ana@example.com","senha":"senha-segura-123"}
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.nome").value("Ana Silva"))
                .andReturn();
        long userId = idFrom(createdUser);

        mockMvc.perform(get("/api/usuarios/{id}", userId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("ana@example.com"));

        mockMvc.perform(put("/api/usuarios/{id}", userId)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"nome":"Ana Souza","email":"ana.souza@example.com"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nome").value("Ana Souza"));

        MvcResult createdFarm = mockMvc.perform(post("/api/fazendas")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"usuarioId":%d,"nome":"Fazenda Horizonte","cidade":"Ribeirao Preto","estado":"SP","areaHectares":120.50}
                                """.formatted(userId)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.usuarioId").value(userId))
                .andReturn();
        long farmId = idFrom(createdFarm);

        mockMvc.perform(get("/api/fazendas/{id}", farmId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.areaHectares").value(120.50));

        mockMvc.perform(put("/api/fazendas/{id}", farmId)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"usuarioId":%d,"nome":"Fazenda Horizonte II","cidade":"Ribeirao Preto","estado":"SP","areaHectares":135.00}
                                """.formatted(userId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nome").value("Fazenda Horizonte II"));

        mockMvc.perform(delete("/api/fazendas/{id}", farmId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/fazendas/{id}", farmId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isNotFound());

        MvcResult secondFarm = mockMvc.perform(post("/api/fazendas")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"usuarioId":%d,"nome":"Fazenda Secundária","cidade":"Campinas","estado":"SP","areaHectares":10.00}
                                """.formatted(userId)))
                .andExpect(status().isCreated())
                .andReturn();
        long secondFarmId = idFrom(secondFarm);

        mockMvc.perform(delete("/api/usuarios/{id}", userId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/usuarios/{id}", userId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/fazendas/{id}", secondFarmId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isNotFound());
    }

    @Test
    void validatesRequiredFieldsAndUnknownUserReferences() throws Exception {
        mockMvc.perform(get("/api/usuarios"))
                .andExpect(status().isUnauthorized());

        String token = register("validation@example.com");
        mockMvc.perform(post("/api/usuarios")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"nome":"","email":"not-an-email","senha":"short"}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details").exists());

        mockMvc.perform(post("/api/fazendas")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"usuarioId":9999,"nome":"Fazenda","cidade":"Cidade","estado":"SP","areaHectares":10}
                                """))
                .andExpect(status().isNotFound());
    }

    @Test
    void loginIssuesJwtAndRejectsIncorrectPassword() throws Exception {
        register("login@example.com");

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"login@example.com","senha":"senha-teste-123"}
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").isNotEmpty());

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"login@example.com","senha":"senha-incorreta"}
                                """))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void actuatorHealthIsPublic() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(result -> {
                    if (result.getResponse().getStatus() == 401) {
                        throw new AssertionError("/actuator/health não deve exigir autenticação.");
                    }
                });
    }

    private String register(String email) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"nome":"Usuário de Teste","email":"%s","senha":"senha-teste-123"}
                                """.formatted(email)))
                .andExpect(status().isCreated())
                .andReturn();
        Matcher matcher = Pattern.compile("\"token\"\\s*:\\s*\"([^\"]+)\"")
                .matcher(result.getResponse().getContentAsString());
        if (!matcher.find()) {
            throw new IllegalStateException("Resposta de registro não contém o token JWT.");
        }
        return matcher.group(1);
    }

    private long idFrom(MvcResult result) throws Exception {
        Matcher matcher = Pattern.compile("\"id\"\\s*:\\s*(\\d+)")
                .matcher(result.getResponse().getContentAsString());
        if (!matcher.find()) {
            throw new IllegalStateException("Resposta HTTP não contém o ID do registro criado.");
        }
        return Long.parseLong(matcher.group(1));
    }
}
