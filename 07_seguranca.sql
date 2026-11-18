-- =====================================================================
-- 07_seguranca.sql  |  Papéis, GRANT/REVOKE e Row-Level Security (RLS)
-- Rode DEPOIS do 03_views.sql e do 04_carga_volume.sql.
-- Pode ser executado como script (Alt + X). É seguro rodar de novo.
-- Os TESTES (parte 6) são manuais: rode bloco a bloco com Ctrl + Enter.
--
-- ATENÇÃO AO NOME: o usuário do docker-compose se chama "aluno" e é
-- SUPERUSUÁRIO. Por isso os papéis do projeto se chamam role_aluno,
-- role_secretaria e role_coordenacao (um papel "aluno" já existe e,
-- além disso, superusuário IGNORA a RLS).
--
-- DUAS CAMADAS DE PROTEÇÃO (explique assim na defesa):
--   1) GRANT/REVOKE decidem O QUE cada papel pode fazer (SELECT, INSERT...)
--      e em quais tabelas/colunas.
--   2) RLS decide QUAIS LINHAS cada papel enxerga ou altera, dentro do que
--      o GRANT já permitiu.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) PAPÉIS
-- Um "papel de grupo" (NOLOGIN) concentra as permissões. Usuários reais
-- (LOGIN) apenas pertencem ao papel e herdam tudo. Para dar ou tirar
-- acesso de alguém, basta incluir/remover do grupo.
-- CREATE ROLE não tem IF NOT EXISTS, por isso o bloco DO.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r       text;
    logins  text[] := ARRAY['u_aluno1', 'u_aluno2', 'u_secretaria', 'u_coordenacao'];
    papeis  text[] := ARRAY['role_aluno', 'role_aluno', 'role_secretaria', 'role_coordenacao'];
    i       int;
BEGIN
    FOREACH r IN ARRAY ARRAY['role_aluno', 'role_secretaria', 'role_coordenacao'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;

    -- usuários de demonstração (senha só para o ambiente acadêmico)
    FOR i IN 1 .. array_length(logins, 1) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = logins[i]) THEN
            EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', logins[i], 'demo123');
        END IF;
        EXECUTE format('GRANT %I TO %I', papeis[i], logins[i]);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 2) VÍNCULO ENTRE O USUÁRIO DO BANCO E O ALUNO
-- A RLS precisa saber "quem é o aluno logado". Guardamos o nome do usuário
-- do banco na própria tb_aluno. Poderia ir no 01_ddl.sql; está aqui para
-- manter a frente de segurança em um arquivo só.
-- (Por que não uma variável de sessão tipo current_setting('app.aluno')?
--  Porque qualquer usuário pode dar SET nela e se passar por outro aluno.
--  current_user vem da autenticação e não pode ser trocado pelo próprio
--  usuário.)
-- ---------------------------------------------------------------------
ALTER TABLE tb_aluno ADD COLUMN IF NOT EXISTS usuario_db name UNIQUE;

UPDATE tb_aluno SET usuario_db = 'u_aluno1' WHERE matricula_aluno = 20250001;
UPDATE tb_aluno SET usuario_db = 'u_aluno2' WHERE matricula_aluno = 20250002;

-- ---------------------------------------------------------------------
-- 3) REVOKE / GRANT  (princípio do menor privilégio: começa sem nada)
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM role_aluno, role_secretaria, role_coordenacao;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;       -- ninguém cria objetos no schema

GRANT USAGE ON SCHEMA public TO role_aluno, role_secretaria, role_coordenacao;

-- role_aluno: só leitura, e só o necessário.
--   * tb_aluno por COLUNAS: o CPF (cpf_aluno) fica de fora de propósito.
--   * as tabelas abaixo são necessárias porque vw_historico_aluno é
--     security_invoker (roda com as permissões de quem consulta).
GRANT SELECT (id_aluno, id_curso, id_curriculo, nome_aluno, matricula_aluno,
              nascimento_aluno, ingresso_aluno, status_aluno, usuario_db)
    ON tb_aluno TO role_aluno;
GRANT SELECT ON tb_matricula, tb_historico, tb_turma, tb_periodo_letivo, tb_disciplina
    TO role_aluno;
GRANT SELECT ON vw_oferta_turmas, vw_vagas_turma, vw_historico_aluno TO role_aluno;

-- role_secretaria: lê tudo; grava alunos, matrículas e históricos;
-- só INSERE no log (trilha de auditoria não se altera).
GRANT SELECT ON ALL TABLES IN SCHEMA public TO role_secretaria;
GRANT INSERT, UPDATE ON tb_aluno, tb_matricula, tb_historico TO role_secretaria;
GRANT INSERT ON tb_log_matricula TO role_secretaria;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO role_secretaria;

-- role_coordenacao: somente leitura de tudo, inclusive a materialized view.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO role_coordenacao;

-- REVOKE explícito: nenhum dos dois pode apagar dados.
REVOKE DELETE, TRUNCATE ON ALL TABLES IN SCHEMA public
    FROM role_secretaria, role_coordenacao;

-- ---------------------------------------------------------------------
-- 4) ROW-LEVEL SECURITY
-- Com a RLS ligada numa tabela, quem não tem NENHUMA política que o
-- autorize não vê linha nenhuma. Por isso cada papel precisa de política.
-- O dono da tabela (aqui, o superusuário "aluno") ignora a RLS.
-- ---------------------------------------------------------------------
ALTER TABLE tb_aluno     ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_matricula ENABLE ROW LEVEL SECURITY;
ALTER TABLE tb_historico ENABLE ROW LEVEL SECURITY;

-- DROP POLICY IF EXISTS deixa o script re-executável.
DROP POLICY IF EXISTS p_aluno_proprio_aluno      ON tb_aluno;
DROP POLICY IF EXISTS p_aluno_proprio_matricula  ON tb_matricula;
DROP POLICY IF EXISTS p_aluno_proprio_historico  ON tb_historico;
DROP POLICY IF EXISTS p_secretaria_aluno         ON tb_aluno;
DROP POLICY IF EXISTS p_secretaria_matricula     ON tb_matricula;
DROP POLICY IF EXISTS p_secretaria_historico     ON tb_historico;
DROP POLICY IF EXISTS p_coordenacao_aluno        ON tb_aluno;
DROP POLICY IF EXISTS p_coordenacao_matricula    ON tb_matricula;
DROP POLICY IF EXISTS p_coordenacao_historico    ON tb_historico;

-- --- role_aluno: enxerga apenas as PRÓPRIAS linhas -------------------
CREATE POLICY p_aluno_proprio_aluno ON tb_aluno
    FOR SELECT TO role_aluno
    USING (usuario_db = current_user);

CREATE POLICY p_aluno_proprio_matricula ON tb_matricula
    FOR SELECT TO role_aluno
    USING (id_aluno IN (SELECT a.id_aluno FROM tb_aluno a
                        WHERE a.usuario_db = current_user));

CREATE POLICY p_aluno_proprio_historico ON tb_historico
    FOR SELECT TO role_aluno
    USING (EXISTS (SELECT 1
                   FROM tb_matricula m
                   JOIN tb_aluno a ON a.id_aluno = m.id_aluno
                   WHERE m.id_matricula = tb_historico.id_matricula
                     AND a.usuario_db = current_user));

-- --- role_secretaria: todas as linhas; o GRANT limita os comandos -----
CREATE POLICY p_secretaria_aluno ON tb_aluno
    FOR ALL TO role_secretaria USING (true) WITH CHECK (true);
CREATE POLICY p_secretaria_matricula ON tb_matricula
    FOR ALL TO role_secretaria USING (true) WITH CHECK (true);
CREATE POLICY p_secretaria_historico ON tb_historico
    FOR ALL TO role_secretaria USING (true) WITH CHECK (true);

-- --- role_coordenacao: lê todas as linhas ----------------------------
CREATE POLICY p_coordenacao_aluno ON tb_aluno
    FOR SELECT TO role_coordenacao USING (true);
CREATE POLICY p_coordenacao_matricula ON tb_matricula
    FOR SELECT TO role_coordenacao USING (true);
CREATE POLICY p_coordenacao_historico ON tb_historico
    FOR SELECT TO role_coordenacao USING (true);

-- ---------------------------------------------------------------------
-- 5) OBSERVAÇÕES PARA A DEFESA
-- * vw_historico_aluno usa security_invoker = true (03_views.sql): a view
--   consulta as tabelas COM as permissões e a RLS de quem a chama. Sem
--   isso ela rodaria com os direitos do dono e furaria a RLS.
-- * vw_oferta_turmas e vw_vagas_turma NÃO são security_invoker de
--   propósito: o aluno precisa ver as vagas totais da turma (contagem de
--   todas as matrículas) sem ver as matrículas dos colegas.
-- * A materialized view não suporta RLS; por isso só recebe GRANT SELECT
--   e contém apenas indicadores agregados (nada por aluno).
-- * Quem executa REFRESH MATERIALIZED VIEW precisa ser o DONO dela
--   (superusuário "aluno"); secretaria e coordenação apenas leem.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 6) TESTES (rode um bloco por vez, com Ctrl + Enter)
-- O superusuário "aluno" pode usar SET ROLE para se passar por qualquer
-- usuário. RESET ROLE volta ao normal. Se um comando der erro, rode
-- ROLLBACK; e RESET ROLE; antes de continuar.
-- ---------------------------------------------------------------------

-- Referência (superusuário): total real de matrículas desses dois alunos
-- SELECT a.matricula_aluno, count(*) AS matriculas
-- FROM tb_matricula m JOIN tb_aluno a USING (id_aluno)
-- WHERE a.matricula_aluno IN (20250001, 20250002) GROUP BY 1;
-- Anote os dois valores: são a REFERÊNCIA. Não são números fixos (dependem de
-- quais ids a carga atribuiu e de matrículas na turma 99 feitas em testes).

-- 6.1) Aluno 1 só enxerga o que é dele
-- SET ROLE u_aluno1;
-- SELECT current_user;                                  -- u_aluno1
-- SELECT count(*) FROM tb_matricula;                    -- = referência do aluno 1
-- SELECT matricula_aluno, nome_aluno FROM tb_aluno;     -- 1 linha
-- SELECT ano_periodo_letivo, semestre, codigo_disciplina, media_final, situacao
-- FROM vw_historico_aluno ORDER BY 1, 2, 3;             -- só o histórico dele
-- SELECT * FROM vw_historico_aluno
-- WHERE matricula_aluno = 20250002;                     -- 0 linhas (outro aluno!)
-- RESET ROLE;

-- 6.2) O que o aluno NÃO pode fazer (cada comando deve dar ERRO)
-- SET ROLE u_aluno1;
-- SELECT * FROM tb_aluno;                  -- ERRO: sem permissão (cpf_aluno é protegido)
-- UPDATE tb_historico SET nota_a1 = 10;    -- ERRO: permission denied
-- SELECT * FROM tb_log_matricula;          -- ERRO: permission denied
-- RESET ROLE;

-- 6.3) Aluno 2 vê o histórico dele, não o do aluno 1
-- SET ROLE u_aluno2;
-- SELECT count(*) FROM tb_matricula;                                     -- = referência do aluno 2
-- SELECT count(*) FROM vw_historico_aluno WHERE matricula_aluno = 20250001;  -- 0
-- RESET ROLE;

-- 6.4) Secretaria: vê tudo, altera, mas não apaga
-- SET ROLE u_secretaria;
-- SELECT count(*) FROM tb_matricula;                      -- todas (120.600)
-- UPDATE tb_historico SET frequencia = frequencia WHERE id_historico = 1;  -- OK
-- DELETE FROM tb_historico WHERE id_historico = 1;        -- ERRO: permission denied
-- RESET ROLE;

-- 6.5) Coordenação: só leitura, inclusive a materialized view
-- SET ROLE u_coordenacao;
-- SELECT count(*) FROM tb_historico;                      -- todas as linhas
-- SELECT * FROM mv_indicadores_disciplina LIMIT 5;        -- OK
-- UPDATE tb_historico SET nota_a1 = 10;                   -- ERRO: permission denied
-- RESET ROLE;

-- Conferência: políticas criadas
-- SELECT tablename, policyname, roles, cmd FROM pg_policies ORDER BY tablename, policyname;
