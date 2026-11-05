-- =====================================================================
-- 05_indices.sql  |  Índices de desempenho (4 índices, 1 parcial)
-- Rode DEPOIS do 04_carga_volume.sql.
-- As medições de EXPLAIN (ANALYZE, BUFFERS) antes/depois de cada índice
-- estão em evidencias_explain.md.
--
-- Contexto: o PostgreSQL cria índices automaticamente para PRIMARY KEY
-- e UNIQUE, mas NÃO para chaves estrangeiras. Os índices abaixo cobrem
-- consultas frequentes que, sem índice, faziam Seq Scan na tabela toda.
--
-- IF NOT EXISTS deixa o script seguro para rodar de novo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Matrículas de um aluno (FK tb_matricula.id_aluno sem índice).
--    O UNIQUE (id_turma, id_aluno) só ajuda buscas que começam por
--    id_turma, não por id_aluno.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_matricula_aluno
    ON tb_matricula (id_aluno);

-- ---------------------------------------------------------------------
-- 2) Trilha de auditoria de uma matrícula (FK tb_log_matricula.matricula_id).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_log_matricula_matricula_id
    ON tb_log_matricula (matricula_id);

-- ---------------------------------------------------------------------
-- 3) ÍNDICE PARCIAL: matrículas canceladas por data.
--    Só ~2% das matrículas têm status_matricula = false. Indexar apenas
--    essas linhas deixa o índice muito menor que um índice completo em
--    data_matricula e mais barato de manter: INSERTs de matrículas
--    ativas não o atualizam. Para o otimizador usá-lo, a consulta
--    precisa conter a condição do índice (status_matricula = false).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_matricula_canceladas_data
    ON tb_matricula (data_matricula)
    WHERE status_matricula = false;

-- ---------------------------------------------------------------------
-- 4) Relatório diário de auditoria (log por data).
--    Cada dia tem ~0,17% das linhas do log: filtro seletivo o bastante
--    para compensar o índice.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS ix_log_ocorrido_em
    ON tb_log_matricula (ocorrido_em);

-- Atualiza as estatísticas para o otimizador enxergar os novos índices.
ANALYZE tb_matricula;
ANALYZE tb_log_matricula;

-- ---------------------------------------------------------------------
-- Conferência: lista os índices criados por este script.
-- ---------------------------------------------------------------------
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE indexname LIKE 'ix\_%'
ORDER BY tablename, indexname;