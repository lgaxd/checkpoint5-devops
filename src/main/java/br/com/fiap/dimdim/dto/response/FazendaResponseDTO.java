package br.com.fiap.dimdim.dto.response;

import java.math.BigDecimal;

public record FazendaResponseDTO(
        Long id,
        Long usuarioId,
        String nome,
        String cidade,
        String estado,
        BigDecimal areaHectares) {
}
