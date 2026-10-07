package br.com.fiap.dimdim.service;

import br.com.fiap.dimdim.dto.request.UsuarioRequestDTO;
import br.com.fiap.dimdim.dto.request.UsuarioUpdateRequestDTO;
import br.com.fiap.dimdim.dto.response.UsuarioResponseDTO;
import br.com.fiap.dimdim.entity.Usuario;
import br.com.fiap.dimdim.exception.BusinessException;
import br.com.fiap.dimdim.exception.ResourceNotFoundException;
import br.com.fiap.dimdim.repository.UsuarioRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class UsuarioService {

    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;

    @Transactional(readOnly = true)
    public List<UsuarioResponseDTO> listar() {
        return usuarioRepository.findAll().stream().map(this::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public UsuarioResponseDTO buscar(Long id) {
        return toResponse(findUsuario(id));
    }

    public UsuarioResponseDTO criar(UsuarioRequestDTO request) {
        if (usuarioRepository.existsByEmail(request.email())) {
            throw new BusinessException("Já existe um usuário com este e-mail.");
        }
        return toResponse(usuarioRepository.save(new Usuario(
                request.nome().trim(),
                request.email().trim(),
                passwordEncoder.encode(request.senha()))));
    }

    public UsuarioResponseDTO atualizar(Long id, UsuarioUpdateRequestDTO request) {
        Usuario usuario = findUsuario(id);
        if (usuarioRepository.existsByEmailAndIdNot(request.email(), id)) {
            throw new BusinessException("Já existe um usuário com este e-mail.");
        }
        usuario.setNome(request.nome().trim());
        usuario.setEmail(request.email().trim());
        return toResponse(usuarioRepository.save(usuario));
    }

    public void excluir(Long id) {
        usuarioRepository.delete(findUsuario(id));
    }

    private Usuario findUsuario(Long id) {
        return usuarioRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Usuário não encontrado: " + id));
    }

    private UsuarioResponseDTO toResponse(Usuario usuario) {
        return new UsuarioResponseDTO(usuario.getId(), usuario.getNome(), usuario.getEmail());
    }
}
