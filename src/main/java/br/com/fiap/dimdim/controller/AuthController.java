package br.com.fiap.dimdim.controller;

import br.com.fiap.dimdim.dto.request.LoginRequestDTO;
import br.com.fiap.dimdim.dto.request.UsuarioRequestDTO;
import br.com.fiap.dimdim.dto.response.AuthResponseDTO;
import br.com.fiap.dimdim.service.AuthService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService authService;

    @PostMapping("/register")
    public ResponseEntity<AuthResponseDTO> registrar(@Valid @RequestBody UsuarioRequestDTO request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(authService.registrar(request));
    }

    @PostMapping("/login")
    public AuthResponseDTO autenticar(@Valid @RequestBody LoginRequestDTO request) {
        return authService.autenticar(request);
    }
}
