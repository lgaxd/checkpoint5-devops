package br.com.fiap.dimdim.controller;

import br.com.fiap.dimdim.dto.request.FazendaRequestDTO;
import br.com.fiap.dimdim.dto.response.FazendaResponseDTO;
import br.com.fiap.dimdim.service.FazendaService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.List;

@RestController
@RequestMapping("/api/fazendas")
@RequiredArgsConstructor
@Tag(name = "Fazendas")
@SecurityRequirement(name = "bearerAuth")
public class FazendaController {

    private final FazendaService fazendaService;

    @GetMapping
    @Operation(summary = "Listar fazendas, opcionalmente por usuário")
    public List<FazendaResponseDTO> listar(@RequestParam(required = false) Long usuarioId) {
        return fazendaService.listar(usuarioId);
    }

    @GetMapping("/{id}")
    @Operation(summary = "Buscar fazenda por ID")
    public FazendaResponseDTO buscar(@PathVariable Long id) {
        return fazendaService.buscar(id);
    }

    @PostMapping
    @Operation(summary = "Cadastrar fazenda")
    public ResponseEntity<FazendaResponseDTO> criar(@Valid @RequestBody FazendaRequestDTO request) {
        FazendaResponseDTO response = fazendaService.criar(request);
        return ResponseEntity.created(URI.create("/api/fazendas/" + response.id())).body(response);
    }

    @PutMapping("/{id}")
    @Operation(summary = "Atualizar fazenda")
    public FazendaResponseDTO atualizar(
            @PathVariable Long id,
            @Valid @RequestBody FazendaRequestDTO request) {
        return fazendaService.atualizar(id, request);
    }

    @DeleteMapping("/{id}")
    @Operation(summary = "Excluir fazenda")
    public ResponseEntity<Void> excluir(@PathVariable Long id) {
        fazendaService.excluir(id);
        return ResponseEntity.noContent().build();
    }
}
