-- =====================================================================
-- 03_views.sql  |  Views (oferta, vagas, histórico) + materialized view
-- Rode DEPOIS do 01_ddl.sql e do 02_carga.sql.
--
-- VIEW = uma consulta salva com nome. Não guarda dados: toda vez que
-- você faz SELECT nela, o banco roda a consulta de novo (dados sempre
-- atuais).
-- MATERIALIZED VIEW = a consulta salva COM o resultado gravado em disco.
-- Leitura rápida, mas os dados ficam "congelados" até o REFRESH.
-- =====================================================================

-- ---------------------------------------------------------------------
-- VIEW 1: oferta de turmas (o que está sendo ofertado, com horários)
-- Para ver só o semestre atual:
--   SELECT * FROM vw_oferta_turmas WHERE ano_periodo_letivo = 2026 AND semestre = 2;
-- ---------------------------------------------------------------------
CREATE VIEW vw_oferta_turmas AS
SELECT p.ano_periodo_letivo,
       p.semestre,
       d.codigo_disciplina,
       d.nome_disciplina,
       t.id_turma,
       t.codigo_turma,
       t.turno_turma,
       pr.nome_professor,
       -- junta todos os horários da turma num único texto: "Seg 19:00-21:00 S101; Ter ..."
       string_agg(
           (ARRAY['Seg','Ter','Qua','Qui','Sex','Sáb','Dom'])[h.dia_semana]
           || ' ' || left(h.inicio_turma_horario::text, 5)
           || '-'  || left(h.fim_turma_horario::text, 5)
           || ' '  || s.codigo_sala,
           '; ' ORDER BY h.dia_semana
       ) AS horarios
FROM tb_turma t
JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina d     ON d.id_disciplina     = t.id_disciplina
JOIN tb_professor pr     ON pr.id_professor     = t.id_professor
LEFT JOIN tb_turma_horario h ON h.id_turma = t.id_turma   -- LEFT: turma sem horário ainda aparece
LEFT JOIN sala s             ON s.id_sala  = h.id_sala
GROUP BY p.ano_periodo_letivo, p.semestre, d.codigo_disciplina, d.nome_disciplina,
         t.id_turma, t.codigo_turma, t.turno_turma, pr.nome_professor;

-- ---------------------------------------------------------------------
-- VIEW 2: vagas por turma
-- vagas_disponiveis = vagas oferecidas - matrículas ativas.
-- Repare que NADA no banco impede vagas_disponiveis de ficar negativa:
-- essa é exatamente a anomalia que a frente de Transações vai explorar.
-- ---------------------------------------------------------------------
CREATE VIEW vw_vagas_turma AS
SELECT t.id_turma,
       p.ano_periodo_letivo,
       p.semestre,
       d.codigo_disciplina,
       d.nome_disciplina,
       t.codigo_turma,
       t.vagas_turma,
       count(m.id_matricula) FILTER (WHERE m.status_matricula)                  AS matriculados,
       t.vagas_turma - count(m.id_matricula) FILTER (WHERE m.status_matricula)  AS vagas_disponiveis
FROM tb_turma t
JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina d     ON d.id_disciplina     = t.id_disciplina
LEFT JOIN tb_matricula m ON m.id_turma = t.id_turma       -- LEFT: turma vazia aparece com 0
GROUP BY t.id_turma, p.ano_periodo_letivo, p.semestre,
         d.codigo_disciplina, d.nome_disciplina, t.codigo_turma, t.vagas_turma;

-- ---------------------------------------------------------------------
-- VIEW 3: histórico do aluno (uma linha por matrícula)
-- security_invoker = true: a view usa as permissões (e a row-level
-- security) de QUEM CONSULTA, e não do dono da view. Sem isso, a RLS
-- da frente de Segurança seria "furada" por esta view.
-- ---------------------------------------------------------------------
CREATE VIEW vw_historico_aluno
WITH (security_invoker = true) AS
SELECT a.id_aluno,
       a.matricula_aluno,
       a.nome_aluno,
       p.ano_periodo_letivo,
       p.semestre,
       d.codigo_disciplina,
       d.nome_disciplina,
       t.codigo_turma,
       h.nota_a1,
       h.nota_a2,
       h.media_final,
       h.frequencia,
       CASE WHEN h.id_matricula IS NULL THEN 'Em andamento'
            WHEN h.situacao             THEN 'Aprovado'
            ELSE                             'Reprovado'
       END AS situacao
FROM tb_aluno a
JOIN tb_matricula m      ON m.id_aluno          = a.id_aluno
JOIN tb_turma t          ON t.id_turma          = m.id_turma
JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina d     ON d.id_disciplina     = t.id_disciplina
LEFT JOIN tb_historico h ON h.id_matricula      = m.id_matricula;  -- LEFT: período atual ainda não tem nota

-- ---------------------------------------------------------------------
-- MATERIALIZED VIEW: indicadores por disciplina e período
-- Considera só matrículas com histórico lançado (períodos encerrados).
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW mv_indicadores_disciplina AS
SELECT p.ano_periodo_letivo,
       p.semestre,
       d.codigo_disciplina,
       d.nome_disciplina,
       count(*)                                         AS total_matriculas,
       count(*) FILTER (WHERE h.situacao)               AS aprovados,
       count(*) FILTER (WHERE NOT h.situacao)           AS reprovados,
       round(100.0 * count(*) FILTER (WHERE h.situacao) / count(*), 1) AS taxa_aprovacao,
       round(avg(h.media_final), 2)                     AS media_geral
FROM tb_historico h
JOIN tb_matricula m      ON m.id_matricula      = h.id_matricula
JOIN tb_turma t          ON t.id_turma          = m.id_turma
JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina d     ON d.id_disciplina     = t.id_disciplina
GROUP BY p.ano_periodo_letivo, p.semestre, d.codigo_disciplina, d.nome_disciplina
WITH DATA;

-- Índice ÚNICO: é o que permite o REFRESH ... CONCURRENTLY (atualizar
-- sem bloquear quem está lendo a view).
CREATE UNIQUE INDEX ux_mv_indicadores_disciplina
    ON mv_indicadores_disciplina (ano_periodo_letivo, semestre, codigo_disciplina);

-- POLÍTICA DE ATUALIZAÇÃO (justificativa para o relatório e a defesa):
-- * Os indicadores só mudam quando notas são lançadas/fechadas no
--   histórico, ou seja, algumas vezes por semestre. Não faz sentido
--   recalcular a cada matrícula (um trigger por linha custaria caro
--   para um dado que quase não muda).
-- * Atualização: manual, logo após o fechamento das notas do período,
--   e agendada 1x por dia de madrugada (ex.: com pg_cron ou cron do
--   sistema) para o caso de correções de notas.
-- * Usamos CONCURRENTLY para a secretaria/coordenação continuarem
--   consultando durante a atualização:
--
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_indicadores_disciplina;
--
-- Trade-off a saber explicar: entre um refresh e outro, a view pode
-- estar desatualizada (dado "velho" em troca de leitura rápida).

-- ---------------------------------------------------------------------
-- TESTES RÁPIDOS (rode um por vez para conferir)
-- ---------------------------------------------------------------------
-- SELECT * FROM vw_oferta_turmas WHERE ano_periodo_letivo = 2026 AND semestre = 2 ORDER BY codigo_disciplina;
-- SELECT * FROM vw_vagas_turma   WHERE ano_periodo_letivo = 2026 AND semestre = 2 ORDER BY codigo_disciplina;
-- SELECT * FROM vw_historico_aluno WHERE matricula_aluno = 20250001 ORDER BY ano_periodo_letivo, semestre;
-- SELECT * FROM mv_indicadores_disciplina ORDER BY ano_periodo_letivo, semestre, codigo_disciplina;
