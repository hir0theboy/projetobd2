# Evidências de EXPLAIN (ANALYZE, BUFFERS)

**Ambiente:** PostgreSQL 17 em Docker.
**Volume de dados** (scripts `02_carga.sql` e `04_carga_volume.sql`): 20.120 alunos,
120.600 matrículas e 120.240 linhas em `tb_log_matricula`.
**Método:** cada medição é a segunda execução da consulta (cache aquecido). Os
índices foram criados com `05_indices.sql` e, logo depois, rodou-se `ANALYZE` na tabela.
A métrica mais estável entre execuções é o número de páginas lidas (`Buffers`); o tempo
em ms varia um pouco de uma execução para outra.

> Nota de edição: em alguns planos abaixo, linhas longas aparecem truncadas com `...`,
> porque a grade do CloudBeaver corta o texto. Para a versão final, substitua esses
> blocos pela saída completa copiada na visão **Text** do resultado.

**Como reproduzir qualquer medição:** apague o índice (`DROP INDEX nome_do_indice;`),
rode a consulta com `EXPLAIN (ANALYZE, BUFFERS)` duas vezes (ANTES), recrie o índice
(comando em `05_indices.sql`), rode `ANALYZE` na tabela e repita a consulta duas
vezes (DEPOIS).

---

## Resumo

| Índice | Tipo | Tempo antes | Tempo depois | Ganho | Páginas antes | Páginas depois |
|---|---|---|---|---|---|---|
| `ix_matricula_aluno` | B-tree (FK) | 13,323 ms | 1,572 ms | ~8,5x | 769 | 4 |
| `ix_log_matricula_matricula_id` | B-tree (FK) | 6,903 ms | 1,235 ms | ~5,6x | 1125 | 4 |
| `ix_matricula_canceladas_data` | **Parcial** | 9,808 ms | 0,573 ms | ~17x | 769 | 3 |
| `ix_log_ocorrido_em` | B-tree | 12,326 ms | 3,256 ms | ~3,8x | 1125 | 84 |

---

## Índice 1: `ix_matricula_aluno` (tb_matricula.id_aluno)

**Consulta:** matrículas de um aluno.
```sql
SELECT m.id_matricula, m.id_turma, m.data_matricula, m.status_matricula
FROM tb_matricula m
WHERE m.id_aluno = 25120;
```

**Antes**
```
Seq Scan on tb_matricula m  (cost=0.00..2276.50 rows=6 width=13) (actual time=12.536..13.296 rows=6 loops=1)
  Filter: (id_aluno = 25120)
  Rows Removed by Filter: 120594
  Buffers: shared hit=769
Planning Time: 0.115 ms
Execution Time: 13.323 ms
```

**Depois**
```
Bitmap Heap Scan on tb_matricula m  (cost=4.34..26.82 rows=6 width=13) (actual time=0.939..1.015 rows=6 loops=1)
  Recheck Cond: (id_aluno = 25120)
  Heap Blocks: exact=2
  Buffers: shared hit=2 read=2
  ->  Bitmap Index Scan on ix_matricula_aluno  (cost=0.00..4.34 rows=6 width=0) (actual time=0.570..0.593 rows=6 loops=1)
        Index Cond: (id_aluno = 25120)
        Buffers: shared read=2
Planning:
  Buffers: shared hit=17 read=1
Planning Time: 5.040 ms
Execution Time: 1.572 ms
```

| Métrica | Antes | Depois | Ganho |
|---|---|---|---|
| Varredura | Seq Scan | Bitmap Index Scan + Bitmap Heap Scan | usa o índice |
| Execution Time | 13,323 ms | 1,572 ms | ~8,5x mais rápido |
| Páginas lidas (hit + read) | 769 | 4 | ~190x menos |
| Custo estimado | 2276,50 | 26,82 | ~85x menor |

**Explicação:** `id_aluno` é chave estrangeira, e o PostgreSQL não cria índice
automaticamente para FK. O `UNIQUE (id_turma, id_aluno)` existente não serve para esta
busca, porque o índice começa por `id_turma`. Sem índice, o banco fazia Seq Scan: lia a
tabela inteira, 769 páginas, e descartava 120.594 linhas para devolver 6. Com o
`ix_matricula_aluno`, o Bitmap Index Scan descobre no índice em quais páginas estão as
linhas do aluno (2 páginas da tabela, `Heap Blocks: exact=2`) e só elas são lidas.

---

## Índice 2: `ix_log_matricula_matricula_id` (tb_log_matricula.matricula_id)

**Consulta:** trilha de auditoria de uma matrícula.
```sql
SELECT id_log_matricula, acao_log, usuario_log, ocorrido_em
FROM tb_log_matricula
WHERE matricula_id = 50000;
```

**Antes**
```
Seq Scan on tb_log_matricula  (cost=0.00..2628.00 ...
  Filter: (matricula_id = 50000)
  Rows Removed by Filter: 120239
  Buffers: shared hit=1125
Planning Time: 0.075 ms
Execution Time: 6.903 ms
```

**Depois**
```
Index Scan using ix_log_matricula_matricula_id on tb_log_matricula ...
  Index Cond: (matricula_id = 50000)
  Buffers: shared hit=4
Planning Time: 1.646 ms
Execution Time: 1.235 ms
```

| Métrica | Antes | Depois | Ganho |
|---|---|---|---|
| Varredura | Seq Scan | Index Scan | usa o índice |
| Execution Time | 6,903 ms | 1,235 ms | ~5,6x mais rápido |
| Páginas lidas (hit + read) | 1125 | 4 | ~280x menos |

**Explicação:** `matricula_id` também é chave estrangeira, sem índice automático. Para
achar a única linha de log de uma matrícula, o banco lia a tabela toda (1125 páginas) e
descartava 120.239 linhas. Com o índice, o `Index Scan` vai direto à linha e lê apenas 4
páginas. Esse é o tipo de consulta de auditoria que seria rodada com frequência.

---

## Índice 3 (PARCIAL): `ix_matricula_canceladas_data`

```sql
CREATE INDEX ix_matricula_canceladas_data
    ON tb_matricula (data_matricula)
    WHERE status_matricula = false;
```

**Consulta:** quantas matrículas foram canceladas em um intervalo de datas.
```sql
SELECT count(*)
FROM tb_matricula
WHERE status_matricula = false
  AND data_matricula BETWEEN '2025-03-01' AND '2025-04-30';
```

**Antes**
```
Aggregate  (cost=2578.81..2578.82 rows=1 width=8 ...
  Buffers: shared hit=769
  ->  Seq Scan on tb_matricula  (cost=0.00..2578.00 rows=3...
        Filter: ((NOT status_matricula) AND (data_matricula >= '...
        Rows Removed by Filter: 120245
        Buffers: shared hit=769
Planning Time: 0.157 ms
Execution Time: 9.808 ms
```

**Depois**
```
Aggregate  (cost=11.48..11.49 rows=1 width=8) (ac...
  Buffers: shared hit=3
  ->  Index Only Scan using ix_matricula_canceladas_data ...
        Index Cond: ((data_matricula >= '2025-03-01'::date) AND ...
        Heap Fetches: 0
        Buffers: shared hit=3
Planning Time: 0.555 ms
Execution Time: 0.573 ms
```

| Métrica | Antes | Depois | Ganho |
|---|---|---|---|
| Varredura | Seq Scan | Index Only Scan | responde só com o índice |
| Execution Time | 9,808 ms | 0,573 ms | ~17x mais rápido |
| Páginas lidas (hit + read) | 769 | 3 | ~256x menos |
| Linhas contadas | 355 (120.600 - 120.245 descartadas) | as mesmas 355 | resultado idêntico |

**Tamanho do índice parcial comparado aos demais** (consulta ao `pg_stat_user_indexes`):
```sql
SELECT indexrelname AS indice,
       pg_size_pretty(pg_relation_size(indexrelid)) AS tamanho
FROM pg_stat_user_indexes
WHERE relname = 'tb_matricula'
ORDER BY pg_relation_size(indexrelid) DESC;
```
```
| A-Z indice | A-Z tamanho |
| :--- | :--- |
| **1** tb_matricula_id_turma_id_aluno_key | 2736 kB |
| **2** tb_matricula_pkey | 2656 kB |
| **3** ix_matricula_aluno | 1336 kB |
| **4** ix_matricula_canceladas_data | 40 kB |
```

**Explicação:** apenas cerca de 2% das matrículas são canceladas
(`status_matricula = false`), então o índice parcial guarda só essas linhas. Ele fica muito
menor que um índice completo em `data_matricula` e custa menos para manter, já que
matrículas ativas (98% dos INSERTs) não o atualizam. A consulta repete a condição do
índice (o plano a mostra como `NOT status_matricula`), o que permite ao otimizador usá-lo.
Como o índice já contém a coluna filtrada e a consulta só faz `count(*)`, o plano é um
`Index Only Scan` com `Heap Fetches: 0`: o banco nem precisa ler a tabela.

---

## Índice 4: `ix_log_ocorrido_em` (tb_log_matricula.ocorrido_em)

**Consulta:** ações registradas em um dia (relatório diário de auditoria).
```sql
SELECT acao_log, count(*)
FROM tb_log_matricula
WHERE ocorrido_em = '2025-06-15'
GROUP BY acao_log;
```

**Antes**
```
GroupAggregate  (cost=2635.60..2637.11 rows=2 w...
  Group Key: acao_log
  Buffers: shared hit=1125
  ->  Sort  (cost=2635.60..2636.10 rows=199 width=7) (actu...
        Sort Key: acao_log
        Sort Method: quicksort  Memory: 25kB
        Buffers: shared hit=1125
        ->  Seq Scan on tb_log_matricula  (cost=0.00..2628.00 ro...
              Filter: (ocorrido_em = '2025-06-15'::date)
              Rows Removed by Filter: 120040
              Buffers: shared hit=1125
Planning Time: 0.170 ms
Execution Time: 12.326 ms
```

**Depois**
```
HashAggregate  (cost=522.10..522.12 rows=2 width...
  Group Key: acao_log
  Batches: 1  Memory Usage: 24kB
  Buffers: shared hit=84
  ->  Bitmap Heap Scan on tb_log_matricula  (cost=5.84..52...
        Recheck Cond: (ocorrido_em = '2025-06-15'::date)
        Heap Blocks: exact=82
        Buffers: shared hit=84
        ->  Bitmap Index Scan on ix_log_ocorrido_em  (cost=0.00....
              Index Cond: (ocorrido_em = '2025-06-15'::date)
              Buffers: shared hit=2
Planning Time: 0.858 ms
Execution Time: 3.256 ms
```

| Métrica | Antes | Depois | Ganho |
|---|---|---|---|
| Varredura | Seq Scan + Sort + GroupAggregate | Bitmap Index/Heap Scan + HashAggregate | usa o índice |
| Execution Time | 12,326 ms | 3,256 ms | ~3,8x mais rápido |
| Páginas lidas (hit + read) | 1125 | 84 | ~13x menos |
| Linhas lidas da tabela | 120.240 (descarta 120.040) | 200 (82 páginas) | |

**Explicação:** o filtro por dia é seletivo (cerca de 200 de 120.240 linhas, 0,17%), então
o índice compensa. O ganho (~3,8x) foi menor que nos outros índices porque as 200 linhas de
um mesmo dia estão espalhadas pela tabela: o banco precisou visitar 82 páginas para
achá-las. Com índice também mudou a agregação: de `Sort + GroupAggregate` para
`HashAggregate`, já que restaram poucas linhas para agrupar.

---

## Conclusão

- **Chaves estrangeiras não ganham índice automático no PostgreSQL.** Duas das quatro
  melhorias vieram de indexar FKs (`id_aluno` e `matricula_id`) usadas em buscas
  frequentes.
- **O índice parcial** foi o de maior ganho (~17x) e é também o mais barato de manter,
  porque cobre só os ~2% de linhas que a consulta realmente precisa.
- **Todo índice tem custo:** ocupa espaço e deixa `INSERT`/`UPDATE` um pouco mais lentos,
  porque precisa ser atualizado junto com a tabela. Por isso só indexamos colunas usadas
  em filtros seletivos.
- **Em tabelas pequenas o índice não muda o plano.** Com as 600 matrículas iniciais, o
  banco preferiria ler a tabela inteira. As medições só mostram ganho depois da carga de
  volume (`04_carga_volume.sql`).
- **O número de páginas lidas é a métrica mais confiável.** O tempo em ms varia entre
  execuções, mas a redução de páginas (769 para 4, 1125 para 4, 769 para 3 e 1125 para 84)
  é estável.
