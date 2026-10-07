package br.com.fiap.dimdim.service;

import br.com.fiap.dimdim.dto.request.LoginRequestDTO;
import br.com.fiap.dimdim.dto.request.UsuarioRequestDTO;
import br.com.fiap.dimdim.dto.response.AuthResponseDTO;
import br.com.fiap.dimdim.dto.response.UsuarioResponseDTO;
import br.com.fiap.dimdim.entity.Usuario;
import br.com.fiap.dimdim.exception.UnauthorizedException;
import br.com.fiap.dimdim.repository.UsuarioRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UsuarioService usuarioService;
    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;

    @Transactional
    public AuthResponseDTO registrar(UsuarioRequestDTO request) {
        UsuarioResponseDTO usuario = usuarioService.criar(request);
        return new AuthResponseDTO(jwtService.createToken(usuario.email()), usuario);
    }

    @Transactional(readOnly = true)
    public AuthResponseDTO autenticar(LoginRequestDTO request) {
        Usuario usuario = usuarioRepository.findByEmail(request.email())
                .filter(found -> passwordEncoder.matches(request.senha(), found.getSenhaHash()))
                .orElseThrow(() -> new UnauthorizedException("E-mail ou senha inválidos."));
        UsuarioResponseDTO response = new UsuarioResponseDTO(usuario.getId(), usuario.getNome(), usuario.getEmail());
        return new AuthResponseDTO(jwtService.createToken(usuario.getEmail()), response);
    }
}
