package br.com.fiap.dimdim.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.math.BigDecimal;

@Entity
@Table(name = "TB_FAZENDA")
@Getter
@Setter
@NoArgsConstructor
public class Fazenda {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "ID_FAZENDA")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ID_USUARIO", nullable = false)
    private Usuario usuario;

    @Column(name = "NM_FAZENDA", nullable = false, length = 150)
    private String nome;

    @Column(name = "DS_CIDADE", nullable = false, length = 100)
    private String cidade;

    @Column(name = "DS_ESTADO", nullable = false, length = 2)
    private String estado;

    @Column(name = "NR_AREA_HECTARES", nullable = false, precision = 10, scale = 2)
    private BigDecimal areaHectares;
}
