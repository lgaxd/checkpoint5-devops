package br.com.fiap.dimdim.dto.response;

import java.time.Instant;
import java.util.Map;

public record ApiErrorDTO(
        int status,
        String message,
        Instant timestamp,
        Map<String, String> details) {
}
