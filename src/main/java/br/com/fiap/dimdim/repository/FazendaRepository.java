package br.com.fiap.dimdim.repository;

import br.com.fiap.dimdim.entity.Fazenda;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface FazendaRepository extends JpaRepository<Fazenda, Long> {

    List<Fazenda> findByUsuarioId(Long usuarioId);
}
