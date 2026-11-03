-- =====================================================================
-- 02_carga.sql  |  Carga de dados (fictícios) para o Sistema de Matrícula
-- Rode DEPOIS do 01_ddl.sql, num banco recém-criado e vazio.
--
-- Resultado esperado:
--   1 campus, 3 cursos, 6 currículos, 12 disciplinas (com pré-requisitos),
--   6 professores, 8 salas, 4 períodos letivos (2025/1 a 2026/2),
--   49 turmas (12 por período + 1 turma "da disputa" em 2026/2),
--   120 alunos, 600 matrículas, 360 históricos.
-- Todos os requisitos mínimos do Marco 1 (100 alunos, 6 turmas, 300
-- matrículas) ficam superados.
--
-- Rodar:  psql -v ON_ERROR_STOP=1 -U aluno -d matricula -f 02_carga.sql
-- (ON_ERROR_STOP faz o psql parar no primeiro erro, em vez de seguir.)
-- =====================================================================

BEGIN;   -- tudo ou nada: se algo falhar, nada é gravado pela metade

-- Semente fixa: random() passa a gerar sempre as mesmas notas.
-- Assim a carga é reproduzível, o que o README exige ("do zero").
SELECT setseed(0.42);

-- ---------------------------------------------------------------------
-- 1) Campus, cursos e currículos
-- ---------------------------------------------------------------------
INSERT INTO tb_campus (nome_campus, cidade)
VALUES ('Asa Sul', 'Brasília');

INSERT INTO tb_curso (id_campus, codigo_curso, nome_curso, grau, ch_total)
SELECT c.id_campus, v.codigo, v.nome, v.grau, v.ch
FROM tb_campus c
CROSS JOIN (VALUES
    ('CCO', 'Ciência da Computação',                  'Bacharelado', 3200),
    ('SIN', 'Sistemas de Informação',                 'Bacharelado', 3000),
    ('ADS', 'Análise e Desenvolvimento de Sistemas',  'Tecnólogo',   2000)
) AS v(codigo, nome, grau, ch)
WHERE c.nome_campus = 'Asa Sul';

-- Cada curso tem um currículo antigo (2022, inativo) e um vigente (2024).
INSERT INTO tb_curriculo (id_curso, ano_vigencia, ativo)
SELECT c.id_curso, a.ano, (a.ano = 2024)
FROM tb_curso c
CROSS JOIN (VALUES (2022), (2024)) AS a(ano);

-- ---------------------------------------------------------------------
-- 2) Disciplinas, grade e árvore de pré-requisitos
-- (simplificação: os 3 cursos compartilham a mesma grade)
-- ---------------------------------------------------------------------
INSERT INTO tb_disciplina (codigo_disciplina, nome_disciplina, ementa, ch_teorico, ch_pratico)
VALUES
    ('PRG1', 'Programação I',               'Lógica e fundamentos de programação.',        40, 40),
    ('MAT1', 'Matemática Discreta',         'Lógica, conjuntos, relações e grafos.',       80,  0),
    ('PRG2', 'Programação II',              'Orientação a objetos.',                       40, 40),
    ('BD1',  'Banco de Dados I',            'Modelagem conceitual e relacional.',          40, 40),
    ('EDA',  'Estruturas de Dados',         'Listas, pilhas, filas, árvores e grafos.',    40, 40),
    ('ENG',  'Engenharia de Software',      'Processos, requisitos e testes.',             60, 20),
    ('BD2',  'Banco de Dados II',           'SQL avançado, transações e administração.',   40, 40),
    ('SO',   'Sistemas Operacionais',       'Processos, memória e arquivos.',              60, 20),
    ('ALG',  'Algoritmos e Complexidade',   'Análise de algoritmos.',                      60, 20),
    ('RED',  'Redes de Computadores',       'Modelo TCP/IP e protocolos.',                 60, 20),
    ('IA',   'Inteligência Artificial',     'Busca, aprendizado e agentes.',               60, 20),
    ('PRJ',  'Projeto Integrador',          'Projeto prático multidisciplinar.',           20, 60);

-- Mesma grade (com o período sugerido) em todos os currículos.
INSERT INTO curriculo_disciplina (id_curriculo, id_disciplina, tipo_curso_disciplina, periodo)
SELECT cur.id_curriculo, d.id_disciplina, 'Obrigatória', m.periodo
FROM tb_curriculo cur
CROSS JOIN (VALUES
    ('PRG1',1), ('MAT1',1), ('PRG2',2), ('BD1',2), ('EDA',3), ('ENG',3),
    ('BD2',4),  ('SO',4),   ('ALG',5),  ('RED',5), ('IA',6),  ('PRJ',6)
) AS m(codigo, periodo)
JOIN tb_disciplina d ON d.codigo_disciplina = m.codigo;

-- Pares (disciplina, pré-requisito). Cadeia mais longa: IA > ALG > EDA > PRG2 > PRG1.
INSERT INTO tb_pre_requisito (id_disciplina, id_requisito)
SELECT d.id_disciplina, r.id_disciplina
FROM (VALUES
    ('PRG2','PRG1'), ('EDA','PRG2'), ('BD1','PRG1'), ('BD2','BD1'),
    ('ENG','PRG2'),  ('SO','EDA'),   ('RED','SO'),   ('ALG','EDA'),
    ('ALG','MAT1'),  ('IA','ALG'),   ('PRJ','BD2'),  ('PRJ','ENG')
) AS p(disc, req)
JOIN tb_disciplina d ON d.codigo_disciplina = p.disc
JOIN tb_disciplina r ON r.codigo_disciplina = p.req;

-- ---------------------------------------------------------------------
-- 3) Períodos, feriados, professores, salas
-- ---------------------------------------------------------------------
INSERT INTO tb_periodo_letivo (ano_periodo_letivo, semestre, data_inicio, data_fim)
VALUES
    (2025, 1, '2025-02-03', '2025-06-27'),
    (2025, 2, '2025-08-04', '2025-12-12'),
    (2026, 1, '2026-02-02', '2026-06-26'),
    (2026, 2, '2026-08-03', '2026-12-11');

INSERT INTO tb_feriado (id_campus, descricao_feriado, data_feriado)
SELECT c.id_campus, f.descricao, f.dia::date
FROM tb_campus c
CROSS JOIN (VALUES
    ('Independência do Brasil',      '2026-09-07'),
    ('Nossa Senhora Aparecida',      '2026-10-12'),
    ('Finados',                      '2026-11-02'),
    ('Proclamação da República',     '2026-11-15'),
    ('Consciência Negra',            '2026-11-20'),
    ('Natal',                        '2026-12-25')
) AS f(descricao, dia);

INSERT INTO tb_professor (matricula_professor, nome_professor, email, titulacao)
VALUES
    ('P0001', 'Ana Souza',      'ana.souza@exemplo.edu.br',      'Doutor'),
    ('P0002', 'Bruno Lima',     'bruno.lima@exemplo.edu.br',     'Mestre'),
    ('P0003', 'Carla Mendes',   'carla.mendes@exemplo.edu.br',   'Doutor'),
    ('P0004', 'Diego Rocha',    'diego.rocha@exemplo.edu.br',    'Mestre'),
    ('P0005', 'Elisa Martins',  'elisa.martins@exemplo.edu.br',  'Especialista'),
    ('P0006', 'Fábio Nunes',    'fabio.nunes@exemplo.edu.br',    'Mestre');

INSERT INTO sala (id_campus, tipo_sala, codigo_sala, capacidade)
SELECT c.id_campus, s.tipo, s.codigo, s.cap
FROM tb_campus c
CROSS JOIN (VALUES
    ('Sala de aula', 'S101', 50), ('Sala de aula', 'S102', 50),
    ('Sala de aula', 'S201', 40), ('Sala de aula', 'S202', 40),
    ('Laboratório',  'L01',  30), ('Laboratório',  'L02',  30),
    ('Laboratório',  'L03',  30), ('Laboratório',  'L04',  30)
) AS s(tipo, codigo, cap);

-- ---------------------------------------------------------------------
-- 4) Turmas e horários
-- Cada período oferece as 12 disciplinas (turma 1). Alternamos turno
-- (disciplina par = MATUTINO, ímpar = NOTURNO) e distribuímos os
-- professores em rodízio. Horários: 2 encontros por semana por turma,
-- sem choque de sala (conferido por aritmética de módulo).
-- ---------------------------------------------------------------------
INSERT INTO tb_turma (id_periodo_letivo, id_professor, id_disciplina, codigo_turma, turno_turma, vagas_turma)
SELECT p.id_periodo_letivo,
       pr.id_professor,
       d.id_disciplina,
       1,
       CASE WHEN d.rn % 2 = 0 THEN 'MATUTINO' ELSE 'NOTURNO' END,
       40
FROM tb_periodo_letivo p
CROSS JOIN (SELECT id_disciplina,
                   row_number() OVER (ORDER BY codigo_disciplina) AS rn
            FROM tb_disciplina) d
JOIN (SELECT id_professor,
             row_number() OVER (ORDER BY id_professor) AS rn
      FROM tb_professor) pr
  ON pr.rn = ((d.rn - 1) % 6) + 1;

INSERT INTO tb_turma_horario (id_turma, id_sala, dia_semana, inicio_turma_horario, fim_turma_horario)
SELECT t.id_turma,
       s.id_sala,
       x.dia,
       CASE WHEN d.rn % 2 = 0 THEN time '08:00' ELSE time '19:00' END,
       CASE WHEN d.rn % 2 = 0 THEN time '10:00' ELSE time '21:00' END
FROM tb_turma t
JOIN (SELECT id_disciplina,
             row_number() OVER (ORDER BY codigo_disciplina) AS rn
      FROM tb_disciplina) d ON d.id_disciplina = t.id_disciplina
JOIN (SELECT id_sala,
             row_number() OVER (ORDER BY id_sala) AS rn
      FROM sala) s ON s.rn = ((d.rn - 1) % 8) + 1
CROSS JOIN LATERAL (VALUES (((d.rn - 1) % 5) + 1),   -- 1º encontro
                           ((d.rn % 5) + 1))         -- 2º encontro
            AS x(dia)                                 -- dia_semana: 1=segunda ... 7=domingo
WHERE t.codigo_turma = 1;

-- Turma "da disputa": 1 única vaga, em 2026/2. Será usada na frente de
-- Transações para reproduzir dois alunos disputando a última vaga.
INSERT INTO tb_turma (id_periodo_letivo, id_professor, id_disciplina, codigo_turma, turno_turma, vagas_turma)
SELECT p.id_periodo_letivo, pr.id_professor, d.id_disciplina, 99, 'NOTURNO', 1
FROM tb_periodo_letivo p, tb_professor pr, tb_disciplina d
WHERE p.ano_periodo_letivo = 2026 AND p.semestre = 2
  AND pr.matricula_professor = 'P0001'
  AND d.codigo_disciplina = 'BD2';

INSERT INTO tb_turma_horario (id_turma, id_sala, dia_semana, inicio_turma_horario, fim_turma_horario)
SELECT t.id_turma, (SELECT min(id_sala) FROM sala), 6, time '08:00', time '10:00'
FROM tb_turma t
WHERE t.codigo_turma = 99;

-- ---------------------------------------------------------------------
-- 5) Alunos (120, fictícios)
-- 1/3 em cada curso, no currículo vigente (2024). CPFs têm 11 dígitos
-- mas NÃO são CPFs reais/válidos: são só números sequenciais.
-- O período de ingresso gira entre 2025/1 e 2026/2 (30 alunos cada).
-- ---------------------------------------------------------------------
INSERT INTO tb_aluno (id_curso, id_curriculo, nome_aluno, cpf_aluno, matricula_aluno,
                      nascimento_aluno, ingresso_aluno, status_aluno)
SELECT c.id_curso,
       cur.id_curriculo,
       (ARRAY['Ana','Bruno','Carla','Diego','Elisa','Fábio','Gabriela','Henrique','Isabela','João'])[1 + g % 10]
         || ' ' ||
       (ARRAY['Silva','Santos','Oliveira','Souza','Pereira','Costa','Ribeiro','Almeida','Carvalho','Gomes'])[1 + (g / 10) % 10]
         || ' ' ||
       (ARRAY['Barbosa','Cardoso','Dias','Freitas','Lopes'])[1 + g % 5],
       lpad((g * 91237)::text, 11, '0'),
       20250000 + g,
       date '2000-01-01' + ((g * 37) % 3000),
       (ARRAY[date '2025-02-03', date '2025-08-04', date '2026-02-02', date '2026-08-03'])[1 + (g - 1) % 4],
       true
FROM generate_series(1, 120) AS g
JOIN (SELECT id_curso,
             row_number() OVER (ORDER BY id_curso) AS rn
      FROM tb_curso) c ON c.rn = ((g - 1) % 3) + 1
JOIN tb_curriculo cur ON cur.id_curso = c.id_curso AND cur.ano_vigencia = 2024;

-- ---------------------------------------------------------------------
-- 6) Matrículas
-- Cada aluno cursa 2 disciplinas por período, seguindo a grade (nível 1
-- no 1º período dele, nível 2 no 2º etc.), então os pré-requisitos
-- sempre foram cumpridos. Total: 600 matrículas.
-- ---------------------------------------------------------------------
WITH al AS (
    SELECT id_aluno,
           ((row_number() OVER (ORDER BY id_aluno) - 1) % 4) + 1 AS s   -- período de ingresso (1..4)
    FROM tb_aluno
),
per AS (
    SELECT id_periodo_letivo, data_inicio,
           row_number() OVER (ORDER BY ano_periodo_letivo, semestre) AS pn   -- 1..4
    FROM tb_periodo_letivo
),
niv(codigo, nivel) AS (
    VALUES ('PRG1',1), ('MAT1',1), ('PRG2',2), ('BD1',2),
           ('EDA',3),  ('ENG',3),  ('BD2',4),  ('SO',4)
)
INSERT INTO tb_matricula (id_turma, id_aluno, data_matricula, status_matricula)
SELECT t.id_turma, al.id_aluno, per.data_inicio - 7, true
FROM al
JOIN per ON per.pn >= al.s
JOIN niv ON niv.nivel = per.pn - al.s + 1
JOIN tb_disciplina d ON d.codigo_disciplina = niv.codigo
JOIN tb_turma t ON t.id_disciplina = d.id_disciplina
               AND t.id_periodo_letivo = per.id_periodo_letivo
               AND t.codigo_turma = 1;

-- ---------------------------------------------------------------------
-- 7) Histórico (só dos períodos já encerrados: antes de 2026/2)
-- Notas de 5,0 a 10,0 (Matemática Discreta: 3,0 a 10,0, para haver
-- reprovações; ela não é pré-requisito de nada que os alunos já cursam).
-- Situação: aprovado se média >= 5 e frequência >= 75.
-- ---------------------------------------------------------------------
INSERT INTO tb_historico (id_matricula, nota_a1, nota_a2, frequencia, situacao, media_final)
SELECT m.id_matricula,
       n.a1, n.a2, n.freq,
       (round((n.a1 + n.a2) / 2, 1) >= 5 AND n.freq >= 75),
       round((n.a1 + n.a2) / 2, 1)
FROM tb_matricula m
JOIN tb_turma t           ON t.id_turma = m.id_turma
JOIN tb_periodo_letivo p  ON p.id_periodo_letivo = t.id_periodo_letivo
JOIN tb_disciplina d      ON d.id_disciplina = t.id_disciplina
CROSS JOIN LATERAL (SELECT CASE WHEN d.codigo_disciplina = 'MAT1' THEN 3.0 ELSE 5.0 END AS base) b
CROSS JOIN LATERAL (SELECT round((b.base + random() * (10 - b.base))::numeric, 1) AS a1,
                           round((b.base + random() * (10 - b.base))::numeric, 1) AS a2,
                           round((75 + random() * 25)::numeric, 2)                AS freq) n
WHERE (p.ano_periodo_letivo * 10 + p.semestre) < 20262;

-- ---------------------------------------------------------------------
-- 8) Log inicial das matrículas do período atual (2026/2)
-- ---------------------------------------------------------------------
INSERT INTO tb_log_matricula (matricula_id, acao_log, detalhe_log)
SELECT m.id_matricula, 'INSERT', 'Matrícula criada pela carga inicial'
FROM tb_matricula m
JOIN tb_turma t          ON t.id_turma = m.id_turma
JOIN tb_periodo_letivo p ON p.id_periodo_letivo = t.id_periodo_letivo
WHERE p.ano_periodo_letivo = 2026 AND p.semestre = 2;

COMMIT;

-- ---------------------------------------------------------------------
-- Conferência: compare com os números esperados lá no topo do arquivo.
-- ---------------------------------------------------------------------
SELECT 'alunos'     AS tabela, count(*) AS linhas FROM tb_aluno
UNION ALL SELECT 'turmas',      count(*) FROM tb_turma
UNION ALL SELECT 'matriculas',  count(*) FROM tb_matricula
UNION ALL SELECT 'historicos',  count(*) FROM tb_historico
UNION ALL SELECT 'horarios',    count(*) FROM tb_turma_horario
UNION ALL SELECT 'pre_requisitos', count(*) FROM tb_pre_requisito;
