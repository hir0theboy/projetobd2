-- =====================================================================
-- 05_indices.sql  |  4 índices (1 parcial) com EXPLAIN antes e depois
-- Rode DEPOIS do 04_carga_volume.sql.
--
--_____________________ARQUIVO SOMENTE PARA ESTUDO/EXPERIMENTOS, NÃO PARA PRODUÇÃO_____________________
--
-- COMO USAR (importante!):
--   NÃO execute o arquivo inteiro como script. Execute BLOCO A BLOCO:
--   selecione o bloco e use Ctrl + Enter. Para cada índice a ordem é:
--     A) EXPLAIN ANTES    -> rode 2 vezes e guarde a SEGUNDA saída
--                            (a 1ª "esquenta" o cache do banco)
--     B) CREATE INDEX + ANALYZE
--     C) EXPLAIN DEPOIS   -> rode 2 vezes e guarde a SEGUNDA saída
--   Cole as saídas no arquivo evidencias_explain.md.
--
-- O QUE OLHAR NA SAÍDA DO EXPLAIN (ANALYZE, BUFFERS):
--   - Tipo do nó: "Seq Scan" (lê a tabela toda) x "Index Scan" /
--     "Index Only Scan" / "Bitmap Heap Scan" (usa o índice).
--   - "Execution Time": tempo real de execução, em ms.
--   - "Buffers: shared hit=X read=Y": páginas de 8 kB lidas (hit = já
--     estavam na memória; read = vieram do disco). Menos = melhor.
--   - "rows=" e "Rows Removed by Filter": quantas linhas foram lidas e
--     descartadas. Seq Scan descartando milhares de linhas é o sinal
--     clássico de que falta um índice.
-- =====================================================================


-- =====================================================================
-- ÍNDICE 1: ix_matricula_aluno  (chave estrangeira sem índice)
-- O PostgreSQL cria índice automático para PRIMARY KEY e UNIQUE, mas
-- NÃO para chave estrangeira. tb_matricula.id_aluno não tem índice (o
-- UNIQUE (id_turma, id_aluno) só ajuda buscas que começam por id_turma).
-- Consulta: matrículas de um aluno.
-- ATENÇÃO: os ids dependem do seu banco (a sequência de ids não volta
-- atrás num ROLLBACK). Confira que o id usado existe e tem matrículas:
--   SELECT id_aluno FROM tb_aluno WHERE matricula_aluno = 30005000;
--   SELECT count(*) FROM tb_matricula WHERE id_aluno = 25120;  -- deve dar 6
-- Se o id for outro, troque 25120 nos dois EXPLAIN abaixo.
-- =====================================================================

-- A) ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id_matricula, m.id_turma, m.data_matricula, m.status_matricula
FROM tb_matricula m
WHERE m.id_aluno = 25120;

-- B) CRIAR
CREATE INDEX ix_matricula_aluno ON tb_matricula (id_aluno);
ANALYZE tb_matricula;

-- C) DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT m.id_matricula, m.id_turma, m.data_matricula, m.status_matricula
FROM tb_matricula m
WHERE m.id_aluno = 25120;


-- =====================================================================
-- ÍNDICE 2: ix_log_matricula_matricula_id  (outra FK sem índice)
-- Consulta: trilha de auditoria de uma matrícula.
-- =====================================================================

-- A) ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_log_matricula, acao_log, usuario_log, ocorrido_em
FROM tb_log_matricula
WHERE matricula_id = 50000;

-- B) CRIAR
CREATE INDEX ix_log_matricula_matricula_id ON tb_log_matricula (matricula_id);
ANALYZE tb_log_matricula;

-- C) DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_log_matricula, acao_log, usuario_log, ocorrido_em
FROM tb_log_matricula
WHERE matricula_id = 50000;


-- =====================================================================
-- ÍNDICE 3 (PARCIAL): ix_matricula_canceladas_data
-- Índice parcial = indexa só as linhas que satisfazem um WHERE. Aqui só
-- ~2% das matrículas são canceladas, então o índice fica ~50x menor que
-- um índice completo em data_matricula, e é mais barato de manter
-- (INSERTs de matrículas ativas nem tocam nele).
-- Consulta: quantas matrículas foram canceladas num intervalo de datas.
-- Atenção: para o otimizador usar o índice parcial, a consulta precisa
-- conter a condição do índice (status_matricula = false).
-- =====================================================================

-- A) ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM tb_matricula
WHERE status_matricula = false
  AND data_matricula BETWEEN '2025-03-01' AND '2025-04-30';

-- B) CRIAR
CREATE INDEX ix_matricula_canceladas_data
    ON tb_matricula (data_matricula)
    WHERE status_matricula = false;
ANALYZE tb_matricula;

-- C) DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM tb_matricula
WHERE status_matricula = false
  AND data_matricula BETWEEN '2025-03-01' AND '2025-04-30';

-- Para a defesa: compare o tamanho dos índices (o parcial é bem menor)
SELECT indexrelname AS indice,
       pg_size_pretty(pg_relation_size(indexrelid)) AS tamanho
FROM pg_stat_user_indexes
WHERE relname = 'tb_matricula'
ORDER BY pg_relation_size(indexrelid) DESC;


-- =====================================================================
-- ÍNDICE 4: ix_log_ocorrido_em
-- Consulta: o que aconteceu num dia (relatório diário de auditoria).
-- Cada dia tem ~200 das ~120 mil linhas (0,17%): seletivo o bastante
-- para valer a pena.
-- =====================================================================

-- A) ANTES
EXPLAIN (ANALYZE, BUFFERS)
SELECT acao_log, count(*)
FROM tb_log_matricula
WHERE ocorrido_em = '2025-06-15'
GROUP BY acao_log;

-- B) CRIAR
CREATE INDEX ix_log_ocorrido_em ON tb_log_matricula (ocorrido_em);
ANALYZE tb_log_matricula;

-- C) DEPOIS
EXPLAIN (ANALYZE, BUFFERS)
SELECT acao_log, count(*)
FROM tb_log_matricula
WHERE ocorrido_em = '2025-06-15'
GROUP BY acao_log;


-- =====================================================================
-- EXTRAS ÚTEIS
-- Para repetir um experimento do zero, apague o índice e rode o bloco A:
--   DROP INDEX ix_matricula_aluno;
-- Para listar os índices criados:
--   SELECT tablename, indexname, indexdef FROM pg_indexes
--   WHERE indexname LIKE 'ix\_%' ORDER BY tablename;
-- =====================================================================