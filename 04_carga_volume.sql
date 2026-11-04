-- =====================================================================
-- 04_carga_volume.sql  |  Carga de volume (para os testes de índice)
-- Rode DEPOIS do 02_carga.sql, UMA ÚNICA VEZ.
--
-- POR QUÊ: com 600 matrículas o banco lê a tabela inteira em
-- microssegundos e o otimizador nem usa índice (ler tudo é mais barato
-- que consultar o índice). Para o "antes e depois" do EXPLAIN mostrar
-- ganho de verdade, precisamos de dezenas de milhares de linhas.
--
-- O que este script adiciona (todos em períodos JÁ ENCERRADOS, então o
-- semestre 2026/2 e a "turma da disputa" não mudam):
--   +20.000 alunos      (matrícula 30000001 em diante)
--   +3.024 turmas       (turmas 2 a 85 de cada disciplina, em 3 períodos)
--   +120.000 matrículas (6 por aluno, no máx. 40 por turma = respeita as vagas)
--   +117.600 históricos (as matrículas canceladas não têm histórico)
--   +120.000 linhas de log
-- Cerca de 2% das matrículas novas são canceladas (status_matricula =
-- false): isso torna o índice PARCIAL útil, pois o filtro é raro.
--
-- Totais esperados no final:
--   alunos 20120 | turmas 3073 | matriculas 120600 | historicos 117960
--   log 120240
-- =====================================================================

BEGIN;

SELECT setseed(0.42);   -- notas reproduzíveis

-- 1) Alunos de volume
INSERT INTO tb_aluno (id_curso, id_curriculo, nome_aluno, cpf_aluno, matricula_aluno,
                      nascimento_aluno, ingresso_aluno, status_aluno)
SELECT c.id_curso,
       cur.id_curriculo,
       'Aluno Volume ' || g,
       lpad((5000000000 + g::bigint * 7919)::text, 11, '0'),   -- 11 dígitos, fictício
       30000000 + g,
       date '1995-01-01' + ((g * 13) % 4000),
       date '2025-02-03',
       true
FROM generate_series(1, 20000) AS g
JOIN (SELECT id_curso,
             row_number() OVER (ORDER BY id_curso) AS rn
      FROM tb_curso) c ON c.rn = ((g - 1) % 3) + 1
JOIN tb_curriculo cur ON cur.id_curso = c.id_curso AND cur.ano_vigencia = 2024;

-- 2) Turmas de volume: códigos 2..85 em cada disciplina, nos 3 períodos encerrados
INSERT INTO tb_turma (id_periodo_letivo, id_professor, id_disciplina, codigo_turma, turno_turma, vagas_turma)
SELECT p.id_periodo_letivo,
       pr.id_professor,
       d.id_disciplina,
       c.n,
       CASE WHEN c.n % 2 = 0 THEN 'MATUTINO' ELSE 'NOTURNO' END,
       40
FROM tb_periodo_letivo p
CROSS JOIN tb_disciplina d
CROSS JOIN generate_series(2, 85) AS c(n)
JOIN (SELECT id_professor,
             row_number() OVER (ORDER BY id_professor) AS rn
      FROM tb_professor) pr ON pr.rn = (c.n % 6) + 1
WHERE (p.ano_periodo_letivo * 10 + p.semestre) < 20262;

-- 3) Matrículas de volume
-- Para o aluno de índice k (0..19999) e j = 0..5, a matrícula n = 6k + j
-- vai para a turma de índice n mod 3024. Assim:
--   - as 6 turmas de um mesmo aluno são sempre diferentes (respeita UNIQUE);
--   - cada turma recebe no máximo 40 alunos (respeita vagas_turma).
-- Quando n é múltiplo de 50 (2%), a matrícula é "cancelada".
WITH bt AS (
    SELECT t.id_turma,
           row_number() OVER (ORDER BY t.id_turma) - 1 AS idx
    FROM tb_turma t
    JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
    WHERE t.codigo_turma >= 2
      AND (p.ano_periodo_letivo * 10 + p.semestre) < 20262
),
ba AS (
    SELECT id_aluno,
           row_number() OVER (ORDER BY id_aluno) - 1 AS k
    FROM tb_aluno
    WHERE matricula_aluno >= 30000000
)
INSERT INTO tb_matricula (id_turma, id_aluno, data_matricula, status_matricula)
SELECT bt.id_turma,
       ba.id_aluno,
       date '2025-01-20' + (((ba.k * 7 + j) % 450))::int,   -- ::int porque k é bigint e date + bigint não existe
       ((ba.k * 6 + j) % 50 <> 0)
FROM ba
CROSS JOIN generate_series(0, 5) AS j
JOIN bt ON bt.idx = (ba.k * 6 + j) % 3024;

-- 4) Histórico de volume (só das matrículas ativas)
INSERT INTO tb_historico (id_matricula, nota_a1, nota_a2, frequencia, situacao, media_final)
SELECT s.id_matricula, s.a1, s.a2, s.freq,
       (round((s.a1 + s.a2) / 2, 1) >= 5 AND s.freq >= 75),
       round((s.a1 + s.a2) / 2, 1)
FROM (SELECT m.id_matricula,
             round((3 + random() * 7)::numeric, 1)   AS a1,
             round((3 + random() * 7)::numeric, 1)   AS a2,
             round((60 + random() * 40)::numeric, 2) AS freq
      FROM tb_matricula m
      JOIN tb_aluno a ON a.id_aluno = m.id_aluno
      WHERE a.matricula_aluno >= 30000000
        AND m.status_matricula) s;

-- 5) Log de volume (1 linha por matrícula nova, datas espalhadas em 600 dias)
INSERT INTO tb_log_matricula (matricula_id, acao_log, detalhe_log, usuario_log, ocorrido_em)
SELECT m.id_matricula,
       CASE WHEN m.status_matricula THEN 'INSERT' ELSE 'CANCELAMENTO' END,
       'Carga de volume',
       'carga',
       date '2025-01-01' + (m.id_matricula % 600)
FROM tb_matricula m
JOIN tb_aluno a ON a.id_aluno = m.id_aluno
WHERE a.matricula_aluno >= 30000000;

COMMIT;

-- Atualiza as estatísticas que o otimizador usa para decidir o plano.
-- (Sem isso ele ainda "acha" que as tabelas são pequenas.)
ANALYZE;

-- Conferência (compare com os totais do topo)
SELECT 'alunos'     AS tabela, count(*) AS linhas FROM tb_aluno
UNION ALL SELECT 'turmas',     count(*) FROM tb_turma
UNION ALL SELECT 'matriculas', count(*) FROM tb_matricula
UNION ALL SELECT 'historicos', count(*) FROM tb_historico
UNION ALL SELECT 'log',        count(*) FROM tb_log_matricula;

-- Se você já tinha criado a materialized view (03_views.sql), ela agora
-- está DESATUALIZADA (foi calculada antes desta carga). Atualize com:
--   REFRESH MATERIALIZED VIEW mv_indicadores_disciplina;