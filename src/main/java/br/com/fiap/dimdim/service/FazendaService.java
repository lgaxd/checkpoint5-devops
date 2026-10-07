package br.com.fiap.dimdim.service;

import br.com.fiap.dimdim.dto.request.FazendaRequestDTO;
import br.com.fiap.dimdim.dto.response.FazendaResponseDTO;
import br.com.fiap.dimdim.entity.Fazenda;
import br.com.fiap.dimdim.entity.Usuario;
import br.com.fiap.dimdim.exception.ResourceNotFoundException;
import br.com.fiap.dimdim.repository.FazendaRepository;
import br.com.fiap.dimdim.repository.UsuarioRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class FazendaService {

    private final FazendaRepository fazendaRepository;
    private final UsuarioRepository usuarioRepository;

    @Transactional(readOnly = true)
    public List<FazendaResponseDTO> listar(Long usuarioId) {
        List<Fazenda> fazendas = usuarioId == null
                ? fazendaRepository.findAll()
                : fazendaRepository.findByUsuarioId(usuarioId);
        return fazendas.stream().map(this::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public FazendaResponseDTO buscar(Long id) {
        return toResponse(findFazenda(id));
    }

    public FazendaResponseDTO criar(FazendaRequestDTO request) {
        Fazenda fazenda = new Fazenda();
        applyRequest(fazenda, request);
        return toResponse(fazendaRepository.save(fazenda));
    }

    public FazendaResponseDTO atualizar(Long id, FazendaRequestDTO request) {
        Fazenda fazenda = findFazenda(id);
        applyRequest(fazenda, request);
        return toResponse(fazendaRepository.save(fazenda));
    }

    public void excluir(Long id) {
        fazendaRepository.delete(findFazenda(id));
    }

    private void applyRequest(Fazenda fazenda, FazendaRequestDTO request) {
        Usuario usuario = usuarioRepository.findById(request.usuarioId())
                .orElseThrow(() -> new ResourceNotFoundException(
                        "Usuário não encontrado: " + request.usuarioId()));
        fazenda.setUsuario(usuario);
        fazenda.setNome(request.nome().trim());
        fazenda.setCidade(request.cidade().trim());
        fazenda.setEstado(request.estado().trim().toUpperCase());
        fazenda.setAreaHectares(request.areaHectares());
    }

    private Fazenda findFazenda(Long id) {
        return fazendaRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Fazenda não encontrada: " + id));
    }

    private FazendaResponseDTO toResponse(Fazenda fazenda) {
        return new FazendaResponseDTO(
                fazenda.getId(),
                fazenda.getUsuario().getId(),
                fazenda.getNome(),
                fazenda.getCidade(),
                fazenda.getEstado(),
                fazenda.getAreaHectares());
    }
}
