package br.com.bookeasy.backend.Flat;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.util.UUID;

@Getter
@Setter
@Entity
@NoArgsConstructor
public class Flat {

    @Id
    @GeneratedValue(strategy = GenerationType.AUTO)
    private UUID id;
    private String nome;
    private String descricao;
    private BigDecimal preco;
    private Integer limite_funcionario;
    private Integer limite_unidades;
    private String periodecidade;
}
