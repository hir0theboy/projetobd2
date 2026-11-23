Junção externa com agregação:
SELECT d.codigo_disciplina, d.nome_disciplina,
count(DISTINCT t.id_turma) AS qtd_turmas,
count(m.id_matricula) AS qtd_matriculas
FROM tb_disciplina d
LEFT JOIN tb_turma t ON t.id_disciplina = d.id_disciplina
LEFT JOIN tb_matricula m ON m.id_turma = t.id_turma
GROUP BY d.id_disciplina, d.codigo_disciplina, d.nome_disciplina
ORDER BY qtd_matriculas DESC;

Recursiva: pré-requisitos diretos e indiretos:
WITH RECURSIVE cadeia AS (
SELECT pr.id_requisito, 1 AS nivel,
ARRAY[pr.id_disciplina, pr.id_requisito] AS caminho
FROM tb_pre_requisito pr
JOIN tb_disciplina d ON d.id_disciplina = pr.id_disciplina
WHERE d.codigo_disciplina = 'PRJ' AND pr.vinculo = 'PRE_REQUISITO'
UNION ALL
SELECT pr.id_requisito, c.nivel + 1, c.caminho || pr.id_requisito
FROM cadeia c
JOIN tb_pre_requisito pr ON pr.id_disciplina = c.id_requisito
WHERE pr.vinculo = 'PRE_REQUISITO' AND pr.id_requisito <> ALL (c.caminho)
)
SELECT min(c.nivel) AS nivel, d.codigo_disciplina, d.nome_disciplina
FROM cadeia c JOIN tb_disciplina d ON d.id_disciplina = c.id_requisito
GROUP BY d.id_disciplina, d.codigo_disciplina, d.nome_disciplina
ORDER BY nivel, d.codigo_disciplina;

Recursiva: disciplinas liberadas para um aluno:
WITH RECURSIVE
aprovadas AS (
SELECT DISTINCT t.id_disciplina
FROM tb_matricula m
JOIN tb_turma t ON t.id_turma = m.id_turma
JOIN tb_historico h ON h.id_matricula = m.id_matricula
WHERE m.id_aluno = 1 AND h.situacao = true
),
req_total AS ( -- fechamento transitivo dos pré-requisitos
SELECT id_disciplina, id_requisito
FROM tb_pre_requisito WHERE vinculo = 'PRE_REQUISITO'
UNION
SELECT rt.id_disciplina, pr.id_requisito
FROM req_total rt
JOIN tb_pre_requisito pr ON pr.id_disciplina = rt.id_requisito
WHERE pr.vinculo = 'PRE_REQUISITO'
)
SELECT cd.periodo, d.codigo_disciplina, d.nome_disciplina
FROM tb_aluno a
JOIN curriculo_disciplina cd ON cd.id_curriculo = a.id_curriculo
JOIN tb_disciplina d ON d.id_disciplina = cd.id_disciplina
Roteiro de estudo: arguição BD2 (15 perguntas)
Page 17 of 24
WHERE a.id_aluno = 1
AND d.id_disciplina NOT IN (SELECT id_disciplina FROM aprovadas)
AND NOT EXISTS (
SELECT 1 FROM req_total rt
WHERE rt.id_disciplina = d.id_disciplina
AND rt.id_requisito NOT IN (SELECT id_disciplina FROM aprovadas))
ORDER BY cd.periodo, d.codigo_disciplina;

Função de janela: ranking e percentil:
WITH media_aluno AS (
SELECT a.id_aluno, a.id_curso, a.nome_aluno,
round(avg(h.media_final), 2) AS media_geral
FROM tb_aluno a
JOIN tb_matricula m ON m.id_aluno = a.id_aluno
JOIN tb_historico h ON h.id_matricula = m.id_matricula
GROUP BY a.id_aluno, a.id_curso, a.nome_aluno
)
SELECT c.codigo_curso, ma.nome_aluno, ma.media_geral,
RANK() OVER (PARTITION BY ma.id_curso ORDER BY ma.media_geral DESC) AS
posicao,
round((PERCENT_RANK() OVER (PARTITION BY ma.id_curso
ORDER BY ma.media_geral) * 100)::numeric,
1) AS percentil
FROM media_aluno ma
JOIN tb_curso c ON c.id_curso = ma.id_curso
ORDER BY c.codigo_curso, posicao;

Função de janela com LAG:
WITH media_periodo AS (
SELECT m.id_aluno, p.ano_periodo_letivo, p.semestre,
round(avg(h.media_final), 2) AS media
FROM tb_matricula m
JOIN tb_turma t ON t.id_turma = m.id_turma
JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_historico h ON h.id_matricula = m.id_matricula
GROUP BY m.id_aluno, p.ano_periodo_letivo, p.semestre
)
SELECT id_aluno, ano_periodo_letivo || '/' || semestre AS periodo, media,
LAG(media) OVER w AS media_anterior,
media - LAG(media) OVER w AS variacao
FROM media_periodo
WINDOW w AS (PARTITION BY id_aluno ORDER BY ano_periodo_letivo, semestre)
ORDER BY id_aluno, ano_periodo_letivo, semestre;

Consultas de reforço:
-- HAVING: turmas com mais de 2 matriculados (o filtro é sobre o grupo, por
isso não é WHERE)
SELECT d.nome_disciplina, t.id_turma, COUNT(*) AS matriculados
FROM tb_matricula m
JOIN tb_turma t ON t.id_turma = m.id_turma
JOIN tb_disciplina d ON d.id_disciplina = t.id_disciplina
GROUP BY d.nome_disciplina, t.id_turma
HAVING COUNT(*) > 2
ORDER BY matriculados DESC, t.id_turma;
-- LEFT JOIN + IS NULL: matrículas ainda sem histórico ("o que está
faltando")
SELECT m.id_matricula, m.id_aluno
FROM tb_matricula m
LEFT JOIN tb_historico h ON h.id_matricula = m.id_matricula
WHERE h.id_historico IS NULL;


