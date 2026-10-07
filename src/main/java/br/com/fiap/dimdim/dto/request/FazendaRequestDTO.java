package br.com.fiap.dimdim.dto.request;

import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

public record FazendaRequestDTO(
        @NotNull @Positive Long usuarioId,
        @NotBlank @Size(max = 150) String nome,
        @NotBlank @Size(max = 100) String cidade,
        @NotBlank @Size(min = 2, max = 2) String estado,
        @NotNull @Positive @Digits(integer = 8, fraction = 2) BigDecimal areaHectares) {
}
