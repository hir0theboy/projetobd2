# Sistema de Matrícula Acadêmica: Projeto de Banco de Dados II

Centro Universitário IESB · Ciência da Computação · Banco de Dados II (CCO072) · 2026/2
Prof. Rodrigo Gonçalves · PostgreSQL 17

Projeto acadêmico que transforma o modelo relacional fornecido pelo professor em um banco
de dados que funciona de verdade: integridade garantida por restrições, desempenho
sustentado por índices, comportamento correto sob acesso concorrente e capacidade de ser
administrado e recuperado.

Os autores e a frente de cada integrante estão em [`AUTORES.md`](AUTORES.md).

---

## Pré-requisitos

- **Docker Desktop** (com `docker compose`)
- **Git**
- Um navegador (os scripts são executados no **CloudBeaver**, que sobe junto com o banco)
- Opcional: outro cliente SQL, como DBeaver ou pgAdmin

## Estrutura do repositório

| Arquivo | Conteúdo |
|---|---|
| `docker-compose.yml` | Sobe o PostgreSQL 17 (banco `matricula`, usuário `aluno`) e o CloudBeaver (porta 8978) |
| `01_ddl.sql` | Domínios, tipos, tabelas, chaves e restrições de integridade |
| `02_carga.sql` | Dados iniciais fictícios (120 alunos, 600 matrículas etc.) |
| `03_views.sql` | 3 views e 1 materialized view de indicadores |
| `04_carga_volume.sql` | Carga em volume (20 mil alunos, 120 mil matrículas) para medir índices |
| `05_indices.sql` | 4 índices, sendo 1 parcial |
| `evidencias_explain.md` | `EXPLAIN (ANALYZE, BUFFERS)` antes e depois de cada índice, com o ganho medido |
| `AUTORES.md` | Autores e frente de cada integrante |

Os scripts são numerados na **ordem de execução**.

---

## Como subir o banco do zero

Os scripts são executados no **CloudBeaver**, a interface web do banco, que já vem no
`docker-compose.yml`.

### 1. Subir os contêineres

```bash
docker compose up -d
docker compose ps
```

O `ps` deve mostrar os serviços `db` e `cloudbeaver` em execução.

> Se a porta 5432 já estiver em uso, troque `"5432:5432"` por `"5433:5432"` no
> `docker-compose.yml` (isso só afeta clientes fora do Docker; o CloudBeaver continua
> usando a porta 5432 internamente).

Na primeira vez, o CloudBeaver pode levar alguns minutos para iniciar. Se a página ficar
carregando sem parar, aguarde e recarregue com `Ctrl + Shift + R` (ou use uma janela
anônima). O comando `docker compose logs cloudbeaver` mostra o andamento.

### 2. Configurar o CloudBeaver (apenas na primeira vez)

1. Abra <http://localhost:8978>.
2. No assistente **Initial server configuration**, mantenha os valores padrão e clique em
   **NEXT**. Na tela seguinte, crie o usuário administrador (nome e senha à sua escolha;
   anote), conclua com **FINISH** e faça login.
3. Clique em **Nova conexão**, escolha **PostgreSQL** e preencha:

   | Campo | Valor |
   |---|---|
   | Host | `db` |
   | Porta | `5432` |
   | Banco de dados | `matricula` |
   | Usuário | `aluno` |
   | Senha | `aluno123` |

4. Salve e abra a conexão.

### 3. Executar os scripts, na ordem

Para **cada** script, de `01` a `05`:

1. Com a conexão selecionada, abra um **editor SQL novo** (botão **SQL** na barra superior).
2. Abra o arquivo `.sql`, copie todo o conteúdo e cole no editor.
3. Execute como **script** com `Alt + X`. (`Ctrl + Enter` executa só um comando, e o
   script precisa rodar inteiro.)

Confira o resumo que o CloudBeaver mostra ao final de cada um:

| Script | Resultado esperado |
|---|---|
| `01_ddl.sql` | 20 comandos executados, sem erro |
| `02_carga.sql` | 22 comandos, 1.596 linhas atualizadas |
| `03_views.sql` | sem erro (3 views, 1 materialized view e 1 índice único) |
| `04_carga_volume.sql` | 11 comandos, 380.624 linhas atualizadas (leva cerca de 1 a 2 minutos) |
| `05_indices.sql` | sem erro; a última consulta lista os 4 índices criados |

Se algum script falhar, rode `ROLLBACK;` sozinho no editor antes de tentar de novo (os
scripts que alteram dados começam com `BEGIN`, e o erro deixa a transação aberta).
**Não rode** `02_carga.sql` nem `04_carga_volume.sql` duas vezes na mesma base.

### 4. Atualizar a materialized view

A materialized view foi criada (script 03) antes da carga em volume (script 04), então
precisa ser atualizada. Em um editor SQL, execute com `Ctrl + Enter`:

```sql
REFRESH MATERIALIZED VIEW mv_indicadores_disciplina;
```

### 5. Conferir

Execute com `Ctrl + Enter`:

```sql
SELECT 'alunos' AS tabela, count(*) AS linhas FROM tb_aluno
UNION ALL SELECT 'turmas',     count(*) FROM tb_turma
UNION ALL SELECT 'matriculas', count(*) FROM tb_matricula
UNION ALL SELECT 'historicos', count(*) FROM tb_historico
UNION ALL SELECT 'log',        count(*) FROM tb_log_matricula;
```

Resultado esperado:

| Tabela | Após o `02_carga.sql` | Após o `04_carga_volume.sql` |
|---|---|---|
| alunos | 120 | 20.120 |
| turmas | 49 | 3.073 |
| matriculas | 600 | 120.600 |
| historicos | 360 | 117.960 |
| log | 240 | 120.240 |

### Recomeçar do zero

```bash
docker compose down -v
```

Isso apaga os contêineres e os volumes (**destrói o banco e também a configuração do
CloudBeaver**). Depois, repita os passos 1 a 5, inclusive o assistente do CloudBeaver.

### Alternativa pelo terminal (sem CloudBeaver)

Os mesmos scripts podem ser executados direto pelo `psql` dentro do contêiner, na ordem.
Em macOS, Linux ou Git Bash:

```bash
for f in 01_ddl 02_carga 03_views 04_carga_volume 05_indices; do
  docker compose cp $f.sql db:/tmp/$f.sql &&
  docker compose exec db psql -v ON_ERROR_STOP=1 -U aluno -d matricula -f /tmp/$f.sql || break
done
docker compose exec db psql -U aluno -d matricula -c "REFRESH MATERIALIZED VIEW mv_indicadores_disciplina;"
```

No PowerShell, rode o par `docker compose cp` e `docker compose exec` de cada script,
um por vez.

---

## Conexão com o banco

| Parâmetro | Valor |
|---|---|
| Host | `db` no CloudBeaver; `localhost` em clientes fora do Docker (DBeaver, pgAdmin) |
| Porta | `5432` |
| Banco | `matricula` |
| Usuário | `aluno` |
| Senha | `aluno123` |

Terminal SQL direto no contêiner:

```bash
docker compose exec db psql -U aluno -d matricula
```

Comandos úteis dentro do `psql`: `\dt` (tabelas), `\d tb_aluno` (estrutura de uma tabela),
`\di` (índices), `\dv` (views), `\q` (sair).


---

## Frentes do projeto e estado atual

### 1. Modelagem física e desempenho: concluída

- DDL completo com restrições de integridade (`01_ddl.sql`).
- 4 índices, incluindo um parcial (`05_indices.sql`).
- `EXPLAIN (ANALYZE, BUFFERS)` antes e depois de cada índice, com o ganho medido:
  [`evidencias_explain.md`](evidencias_explain.md).

| Índice | Tempo antes | Tempo depois | Páginas lidas antes e depois |
|---|---|---|---|
| `ix_matricula_aluno` | 13,3 ms | 1,6 ms | 769 e 4 |
| `ix_log_matricula_matricula_id` | 6,9 ms | 1,2 ms | 1125 e 4 |
| `ix_matricula_canceladas_data` (parcial) | 9,8 ms | 0,6 ms | 769 e 3 |
| `ix_log_ocorrido_em` | 12,3 ms | 3,3 ms | 1125 e 84 |

### 2. Transações e concorrência: em andamento

A fazer: reprodução da anomalia na disputa pela última vaga, duas correções (bloqueio
explícito e nível de isolamento) e comparação fundamentada entre as abordagens.

### 3. Administração e operação: em andamento

- Views (oferta, vagas, histórico) e materialized view de indicadores: **feitas**
  (`03_views.sql`). A política de atualização está justificada nos comentários do script.
- Papéis `aluno`, `secretaria` e `coordenacao` com `GRANT`/`REVOKE` e row-level security:
  **a fazer**.
- Backup e restauração reproduzíveis: **a fazer**.

---

## Notas de uso

- **Os ids não voltam atrás num `ROLLBACK`.** A numeração automática (identity) continua
  de onde parou, então os ids exatos podem diferir entre ambientes. Os testes de
  `EXPLAIN` usam, por exemplo, `id_aluno = 25120`; confira o id com
  `SELECT id_aluno FROM tb_aluno WHERE matricula_aluno = 30005000;` e ajuste se preciso.
- Os scripts que alteram dados usam `BEGIN`/`COMMIT`. Se um deles falhar no CloudBeaver,
  rode `ROLLBACK;` antes de tentar de novo.
- No CloudBeaver, `Alt + X` executa o script inteiro e `Ctrl + Enter` executa só o comando
  em que o cursor está. Para copiar planos de `EXPLAIN` sem texto cortado, troque o
  resultado da visão **Grid** para **Text**.
- Não rode `02_carga.sql` nem `04_carga_volume.sql` duas vezes na mesma base. Para repetir,
  use `docker compose down -v` e recomece do passo 1.
