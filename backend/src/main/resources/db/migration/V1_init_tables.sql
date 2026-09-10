-- =========================================================================
-- BARBEARIA — MODELO DE DADOS (PostgreSQL 15+)
-- Ordem de criação respeita dependências de FK.
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "btree_gist"; -- EXCLUDE USING GIST com colunas escalares
CREATE EXTENSION IF NOT EXISTS "citext";     -- e-mail case-insensitive

-- -------------------------------------------------------------------------
-- DOMÍNIOS / ENUMS
-- -------------------------------------------------------------------------

CREATE TYPE tipo_usuario AS ENUM ('CLIENTE', 'PROFISSIONAL', 'ADMIN');

CREATE TYPE status_conta AS ENUM ('ATIVO', 'INATIVO', 'BLOQUEADO', 'PENDENTE_VERIFICACAO');

CREATE TYPE tipo_token AS ENUM ('RECUPERACAO_SENHA', 'VERIFICACAO_EMAIL');

CREATE TYPE status_agendamento AS ENUM (
    'PENDENTE',
    'CONFIRMADO',
    'EM_ATENDIMENTO',
    'CONCLUIDO',
    'CANCELADO',
    'NAO_COMPARECEU',
    'REAGENDADO'
);

CREATE TYPE origem_agendamento AS ENUM ('CLIENTE_APP', 'ADMIN_PAINEL', 'RECEPCAO');

CREATE TYPE tipo_bloqueio AS ENUM (
    'FERIAS', 'FOLGA', 'ALMOCO', 'MANUTENCAO',
    'REUNIAO', 'INDISPONIBILIDADE', 'FERIADO', 'ADMINISTRATIVO'
);

CREATE TYPE status_pagamento AS ENUM ('PENDENTE', 'APROVADO', 'RECUSADO', 'CANCELADO', 'ESTORNADO');

CREATE TYPE status_moderacao AS ENUM ('PUBLICADA', 'EM_ANALISE', 'REMOVIDA');

CREATE TYPE canal_notificacao AS ENUM ('EMAIL', 'SMS', 'PUSH', 'WHATSAPP');

CREATE TYPE tipo_notificacao AS ENUM (
    'AGENDAMENTO_CONFIRMADO', 'LEMBRETE', 'CANCELAMENTO',
    'REAGENDAMENTO', 'CONCLUSAO', 'OUTRO'
);

CREATE TYPE operacao_auditoria AS ENUM ('INSERT', 'UPDATE', 'DELETE');

-- -------------------------------------------------------------------------
-- 1. UNIDADES (filiais)
-- -------------------------------------------------------------------------
CREATE TABLE unidades (
                          id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                          nome            VARCHAR(120) NOT NULL,
                          endereco        VARCHAR(255),
                          telefone        VARCHAR(20),
                          timezone        VARCHAR(60) NOT NULL DEFAULT 'America/Sao_Paulo',
                          ativo           BOOLEAN NOT NULL DEFAULT TRUE,
                          criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
                          atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------------
-- 2. USUARIOS (identidade / autenticação — separada do perfil)
-- -------------------------------------------------------------------------
CREATE TABLE usuarios (
                          id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                          email               CITEXT NOT NULL,
                          telefone            VARCHAR(20),
                          senha_hash          TEXT NOT NULL,              -- Argon2id / bcrypt
                          tipo                tipo_usuario NOT NULL,
                          status              status_conta NOT NULL DEFAULT 'PENDENTE_VERIFICACAO',
                          email_verificado_em TIMESTAMPTZ,
                          ultimo_login_em     TIMESTAMPTZ,
                          criado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
                          atualizado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
                          CONSTRAINT uq_usuarios_email UNIQUE (email)
);

CREATE INDEX idx_usuarios_tipo_status ON usuarios (tipo, status);

CREATE TABLE tokens_autenticacao (
                                     id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                     usuario_id      UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
                                     tipo            tipo_token NOT NULL,
                                     token_hash      TEXT NOT NULL,
                                     expira_em       TIMESTAMPTZ NOT NULL,
                                     usado_em        TIMESTAMPTZ,
                                     criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
                                     CONSTRAINT uq_tokens_hash UNIQUE (token_hash)
);

CREATE INDEX idx_tokens_usuario ON tokens_autenticacao (usuario_id, tipo) WHERE usado_em IS NULL;

-- -------------------------------------------------------------------------
-- 3. RBAC (cargos administrativos e permissões)
-- -------------------------------------------------------------------------
CREATE TABLE cargos (
                        id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                        nome        VARCHAR(60) NOT NULL,
                        descricao   VARCHAR(255),
                        CONSTRAINT uq_cargos_nome UNIQUE (nome)
);

CREATE TABLE permissoes (
                            id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                            chave       VARCHAR(80) NOT NULL,   -- ex: 'servico.editar', 'agendamento.cancelar'
                            descricao   VARCHAR(255),
                            CONSTRAINT uq_permissoes_chave UNIQUE (chave)
);

CREATE TABLE cargo_permissoes (
                                  cargo_id        SMALLINT NOT NULL REFERENCES cargos(id) ON DELETE CASCADE,
                                  permissao_id    SMALLINT NOT NULL REFERENCES permissoes(id) ON DELETE CASCADE,
                                  PRIMARY KEY (cargo_id, permissao_id)
);

CREATE TABLE administradores (
                                 usuario_id      UUID PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
                                 cargo_id        SMALLINT NOT NULL REFERENCES cargos(id),
                                 nome            VARCHAR(150) NOT NULL,
                                 unidade_id      UUID REFERENCES unidades(id),
                                 criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
                                 atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------------
-- 4. CLIENTES
-- -------------------------------------------------------------------------
CREATE TABLE clientes (
                          usuario_id      UUID PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
                          nome            VARCHAR(120) NOT NULL,
                          sobrenome       VARCHAR(120),
                          data_nascimento DATE,
                          status          status_conta NOT NULL DEFAULT 'ATIVO',
                          criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
                          atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
                          ultimo_acesso_em TIMESTAMPTZ
);

-- -------------------------------------------------------------------------
-- 5. PROFISSIONAIS
-- -------------------------------------------------------------------------
CREATE TABLE profissionais (
                               id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                               usuario_id          UUID UNIQUE REFERENCES usuarios(id) ON DELETE SET NULL, -- login opcional
                               unidade_id          UUID NOT NULL REFERENCES unidades(id),
                               nome                VARCHAR(120) NOT NULL,
                               telefone            VARCHAR(20),
                               especialidades       VARCHAR(255),
                               status              status_conta NOT NULL DEFAULT 'ATIVO',
                               contratado_em       DATE NOT NULL DEFAULT CURRENT_DATE,
                               criado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
                               atualizado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profissionais_unidade_status ON profissionais (unidade_id, status);

-- -------------------------------------------------------------------------
-- 6. SERVIÇOS
-- -------------------------------------------------------------------------
CREATE TABLE categorias_servico (
                                    id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                    nome        VARCHAR(80) NOT NULL,
                                    ativo       BOOLEAN NOT NULL DEFAULT TRUE,
                                    CONSTRAINT uq_categoria_nome UNIQUE (nome)
);

CREATE TABLE servicos (
                          id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                          categoria_id    SMALLINT NOT NULL REFERENCES categorias_servico(id),
                          nome            VARCHAR(120) NOT NULL,
                          descricao       TEXT,
                          duracao_minutos SMALLINT NOT NULL,
                          preco           NUMERIC(10,2) NOT NULL,
                          ativo           BOOLEAN NOT NULL DEFAULT TRUE,
                          criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
                          atualizado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
                          CONSTRAINT chk_servico_duracao CHECK (duracao_minutos > 0),
                          CONSTRAINT chk_servico_preco CHECK (preco >= 0)
);

CREATE INDEX idx_servicos_ativo ON servicos (ativo) WHERE ativo = TRUE;
CREATE INDEX idx_servicos_categoria ON servicos (categoria_id);

CREATE TABLE profissional_servico (
                                      profissional_id UUID NOT NULL REFERENCES profissionais(id) ON DELETE CASCADE,
                                      servico_id      UUID NOT NULL REFERENCES servicos(id) ON DELETE CASCADE,
                                      PRIMARY KEY (profissional_id, servico_id)
);

CREATE INDEX idx_profserv_servico ON profissional_servico (servico_id);

-- -------------------------------------------------------------------------
-- 7. AGENDA: funcionamento, jornada, bloqueios
-- -------------------------------------------------------------------------
CREATE TABLE horarios_funcionamento (
                                        id              SERIAL PRIMARY KEY,
                                        unidade_id      UUID NOT NULL REFERENCES unidades(id) ON DELETE CASCADE,
                                        dia_semana      SMALLINT NOT NULL, -- 0=domingo .. 6=sábado
                                        hora_abertura   TIME NOT NULL,
                                        hora_fechamento TIME NOT NULL,
                                        CONSTRAINT chk_horfunc_intervalo CHECK (hora_fechamento > hora_abertura),
                                        CONSTRAINT chk_horfunc_dia CHECK (dia_semana BETWEEN 0 AND 6),
                                        CONSTRAINT uq_horfunc UNIQUE (unidade_id, dia_semana, hora_abertura)
);

CREATE TABLE jornada_profissional (
                                      id              SERIAL PRIMARY KEY,
                                      profissional_id UUID NOT NULL REFERENCES profissionais(id) ON DELETE CASCADE,
                                      dia_semana      SMALLINT NOT NULL,
                                      hora_inicio     TIME NOT NULL,
                                      hora_fim        TIME NOT NULL,
                                      CONSTRAINT chk_jornada_intervalo CHECK (hora_fim > hora_inicio),
                                      CONSTRAINT chk_jornada_dia CHECK (dia_semana BETWEEN 0 AND 6),
                                      CONSTRAINT uq_jornada UNIQUE (profissional_id, dia_semana, hora_inicio)
);

CREATE TABLE bloqueios_agenda (
                                  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                  unidade_id      UUID NOT NULL REFERENCES unidades(id),
                                  profissional_id UUID REFERENCES profissionais(id) ON DELETE CASCADE, -- NULL = bloqueio da unidade inteira
                                  tipo            tipo_bloqueio NOT NULL,
                                  inicio          TIMESTAMPTZ NOT NULL,
                                  fim             TIMESTAMPTZ NOT NULL,
                                  motivo          VARCHAR(255),
                                  criado_por      UUID REFERENCES usuarios(id),
                                  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
                                  CONSTRAINT chk_bloqueio_intervalo CHECK (fim > inicio),
    -- impede sobreposição de bloqueios do MESMO profissional
                                  EXCLUDE USING GIST (
        profissional_id WITH =,
        tstzrange(inicio, fim) WITH &&
    ) WHERE (profissional_id IS NOT NULL)
);

CREATE INDEX idx_bloqueios_periodo ON bloqueios_agenda USING GIST (tstzrange(inicio, fim));

-- -------------------------------------------------------------------------
-- 8. AGENDAMENTOS
-- -------------------------------------------------------------------------
CREATE TABLE agendamentos (
                              id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                              cliente_id          UUID NOT NULL REFERENCES clientes(usuario_id),
                              unidade_id          UUID NOT NULL REFERENCES unidades(id),
                              status              status_agendamento NOT NULL DEFAULT 'PENDENTE',
                              origem              origem_agendamento NOT NULL DEFAULT 'CLIENTE_APP',
                              observacoes         TEXT,
                              motivo_cancelamento VARCHAR(255),
                              agendamento_origem_id UUID REFERENCES agendamentos(id), -- aponta para o agendamento anterior em caso de reagendamento
                              criado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
                              atualizado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_agendamentos_cliente ON agendamentos (cliente_id, criado_em DESC);
CREATE INDEX idx_agendamentos_unidade_status ON agendamentos (unidade_id, status);

CREATE TABLE itens_agendamento (
                                   id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                   agendamento_id      UUID NOT NULL REFERENCES agendamentos(id) ON DELETE CASCADE,
                                   servico_id          UUID NOT NULL REFERENCES servicos(id),
                                   profissional_id     UUID NOT NULL REFERENCES profissionais(id),
                                   ordem               SMALLINT NOT NULL DEFAULT 1,
                                   hora_inicio         TIMESTAMPTZ NOT NULL,
                                   hora_fim            TIMESTAMPTZ NOT NULL,
                                   preco_aplicado      NUMERIC(10,2) NOT NULL,     -- snapshot do preço no momento da reserva
                                   duracao_aplicada    SMALLINT NOT NULL,           -- snapshot da duração
                                   status              status_agendamento NOT NULL DEFAULT 'PENDENTE',
                                   observacoes         VARCHAR(255),
                                   CONSTRAINT chk_item_intervalo CHECK (hora_fim > hora_inicio),
                                   CONSTRAINT chk_item_preco CHECK (preco_aplicado >= 0),
                                   CONSTRAINT chk_item_duracao CHECK (duracao_aplicada > 0),
    -- REGRA CENTRAL ANTI DOUBLE-BOOKING:
    -- nenhum profissional pode ter dois itens de agendamento com intervalos sobrepostos,
    -- exceto os que já estão CANCELADO / NAO_COMPARECEU.
                                   EXCLUDE USING GIST (
        profissional_id WITH =,
        tstzrange(hora_inicio, hora_fim) WITH &&
    ) WHERE (status NOT IN ('CANCELADO', 'NAO_COMPARECEU'))
);

CREATE INDEX idx_itens_agendamento_agendamento ON itens_agendamento (agendamento_id, ordem);
CREATE INDEX idx_itens_agendamento_profissional_periodo
    ON itens_agendamento USING GIST (profissional_id, tstzrange(hora_inicio, hora_fim));

CREATE TABLE historico_agendamento (
                                       id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                       agendamento_id  UUID NOT NULL REFERENCES agendamentos(id) ON DELETE CASCADE,
                                       status_anterior status_agendamento,
                                       status_novo     status_agendamento NOT NULL,
                                       alterado_por    UUID REFERENCES usuarios(id),
                                       motivo          VARCHAR(255),
                                       criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_historico_agendamento ON historico_agendamento (agendamento_id, criado_em);

-- -------------------------------------------------------------------------
-- 9. PAGAMENTOS
-- -------------------------------------------------------------------------
CREATE TABLE formas_pagamento (
                                  id          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                                  nome        VARCHAR(40) NOT NULL,   -- DINHEIRO, PIX, DEBITO, CREDITO, OUTRO
                                  ativo       BOOLEAN NOT NULL DEFAULT TRUE,
                                  CONSTRAINT uq_forma_pagamento UNIQUE (nome)
);

CREATE TABLE pagamentos (
                            id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                            agendamento_id      UUID NOT NULL REFERENCES agendamentos(id),
                            forma_pagamento_id  SMALLINT NOT NULL REFERENCES formas_pagamento(id),
                            valor               NUMERIC(10,2) NOT NULL,
                            desconto            NUMERIC(10,2) NOT NULL DEFAULT 0,
                            valor_final         NUMERIC(10,2) NOT NULL,
                            status              status_pagamento NOT NULL DEFAULT 'PENDENTE',
                            identificador_externo VARCHAR(120), -- id da transação na adquirente/PSP
                            criado_em           TIMESTAMPTZ NOT NULL DEFAULT now(),
                            pago_em             TIMESTAMPTZ,
                            CONSTRAINT chk_pagamento_valor CHECK (valor >= 0),
                            CONSTRAINT chk_pagamento_desconto CHECK (desconto >= 0 AND desconto <= valor),
                            CONSTRAINT chk_pagamento_final CHECK (valor_final = valor - desconto)
);

CREATE INDEX idx_pagamentos_agendamento ON pagamentos (agendamento_id);
CREATE INDEX idx_pagamentos_status ON pagamentos (status);

-- -------------------------------------------------------------------------
-- 10. AVALIAÇÕES
-- -------------------------------------------------------------------------
CREATE TABLE avaliacoes (
                            id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                            agendamento_id  UUID NOT NULL REFERENCES agendamentos(id),
                            cliente_id      UUID NOT NULL REFERENCES clientes(usuario_id),
                            profissional_id UUID NOT NULL REFERENCES profissionais(id),
                            nota            SMALLINT NOT NULL,
                            comentario      TEXT,
                            status          status_moderacao NOT NULL DEFAULT 'PUBLICADA',
                            criado_em       TIMESTAMPTZ NOT NULL DEFAULT now(),
                            CONSTRAINT chk_avaliacao_nota CHECK (nota BETWEEN 1 AND 5),
                            CONSTRAINT uq_avaliacao_agendamento UNIQUE (agendamento_id) -- 1 avaliação por atendimento
);

CREATE INDEX idx_avaliacoes_profissional ON avaliacoes (profissional_id);

-- -------------------------------------------------------------------------
-- 11. NOTIFICAÇÕES
-- -------------------------------------------------------------------------
CREATE TABLE notificacoes (
                              id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                              usuario_id      UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
                              tipo            tipo_notificacao NOT NULL,
                              canal           canal_notificacao NOT NULL,
                              titulo          VARCHAR(150) NOT NULL,
                              mensagem        TEXT NOT NULL,
                              lida            BOOLEAN NOT NULL DEFAULT FALSE,
                              tentativas_envio SMALLINT NOT NULL DEFAULT 0,
                              enviado_em      TIMESTAMPTZ,
                              lido_em         TIMESTAMPTZ,
                              criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notificacoes_usuario ON notificacoes (usuario_id, lida);

-- -------------------------------------------------------------------------
-- 12. AUDITORIA
-- -------------------------------------------------------------------------
CREATE TABLE auditoria (
                           id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                           usuario_id      UUID REFERENCES usuarios(id),
                           entidade        VARCHAR(60) NOT NULL,
                           registro_id     TEXT NOT NULL,
                           operacao        operacao_auditoria NOT NULL,
                           dados_anteriores JSONB,
                           dados_novos     JSONB,
                           ip_origem       INET,
                           criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_auditoria_entidade ON auditoria (entidade, registro_id);
CREATE INDEX idx_auditoria_usuario ON auditoria (usuario_id, criado_em);

-- =========================================================================
-- FUNÇÃO/TRIGGER GENÉRICA — atualiza "atualizado_em" automaticamente
-- (única automação realmente necessária; evita duplicar lógica em cada UPDATE)
-- =========================================================================
CREATE OR REPLACE FUNCTION trg_set_atualizado_em() RETURNS TRIGGER AS $$
BEGIN
    NEW.atualizado_em = now();
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_atualizado_em_usuarios BEFORE UPDATE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();
CREATE TRIGGER set_atualizado_em_clientes BEFORE UPDATE ON clientes
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();
CREATE TRIGGER set_atualizado_em_profissionais BEFORE UPDATE ON profissionais
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();
CREATE TRIGGER set_atualizado_em_servicos BEFORE UPDATE ON servicos
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();
CREATE TRIGGER set_atualizado_em_agendamentos BEFORE UPDATE ON agendamentos
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();
CREATE TRIGGER set_atualizado_em_unidades BEFORE UPDATE ON unidades
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();
CREATE TRIGGER set_atualizado_em_administradores BEFORE UPDATE ON administradores
    FOR EACH ROW EXECUTE FUNCTION trg_set_atualizado_em();