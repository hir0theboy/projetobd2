# Backup e restauração (PostgreSQL 17 em Docker)

Procedimento reproduzível do zero. Todos os comandos são executados na pasta do
repositório (onde está o `docker-compose.yml`), com os contêineres no ar
(`docker compose up -d`).

> Os comandos gravam o arquivo **dentro do contêiner** e depois o copiam para o
> computador com `docker compose cp`. Isso evita redirecionar a saída com `>`,
> que corrompe arquivos binários no PowerShell do Windows.

## O que é salvo

| Arquivo | Conteúdo | Ferramenta |
|---|---|---|
| `backups/matricula.dump` | Banco `matricula`: tabelas, dados, views, materialized view, índices, políticas de RLS e permissões. Formato custom (`-Fc`), compactado. | `pg_dump` |
| `backups/globais.sql` | Objetos **globais** do servidor: os papéis (`role_aluno`, `u_aluno1`...). **O `pg_dump` não salva papéis**, e sem eles a restauração perde GRANTs e políticas. | `pg_dumpall --globals-only` |

Coloque `backups/` no `.gitignore` se não quiser versionar os arquivos.

## 1. Fazer o backup

```bash
mkdir -p backups

docker compose exec db pg_dump -U aluno -d matricula -Fc -f /tmp/matricula.dump
docker compose exec db pg_dumpall -U aluno --globals-only -f /tmp/globais.sql

docker compose cp db:/tmp/matricula.dump ./backups/matricula.dump
docker compose cp db:/tmp/globais.sql    ./backups/globais.sql
```

(No PowerShell: `mkdir backups` no lugar do primeiro comando.)

Conferir o conteúdo do dump sem restaurar:

```bash
docker compose exec db pg_restore -l /tmp/matricula.dump | head -30
```

## 2. Restaurar em um banco novo (demonstração ao vivo, a mais segura)

Restaura o backup em `matricula_restaurado`, sem tocar no banco original.

```bash
docker compose exec db psql -U aluno -d postgres -c "CREATE DATABASE matricula_restaurado;"
docker compose exec db pg_restore -U aluno -d matricula_restaurado /tmp/matricula.dump
```

Conferir que os dados voltaram (a contagem deve ser igual à do banco original):

```bash
docker compose exec db psql -U aluno -d matricula_restaurado -c "SELECT count(*) AS alunos FROM tb_aluno;"
docker compose exec db psql -U aluno -d matricula_restaurado -c "SELECT count(*) AS matriculas FROM tb_matricula;"
docker compose exec db psql -U aluno -d matricula_restaurado -c "SELECT policyname, tablename FROM pg_policies ORDER BY 2, 1;"
```

Esperado: 20.120 alunos, 120.600 matrículas e as 9 políticas de RLS.

Para limpar depois da demonstração:

```bash
docker compose exec db psql -U aluno -d postgres -c "DROP DATABASE matricula_restaurado;"
```

## 3. Simulação de desastre (restaurar no lugar)

Apaga dados de propósito e recupera pelo backup.

```bash
# 1) desastre: some com o histórico inteiro
docker compose exec db psql -U aluno -d matricula -c "DELETE FROM tb_historico;"
docker compose exec db psql -U aluno -d matricula -c "SELECT count(*) FROM tb_historico;"   # 0

# 2) recuperação: recria o banco a partir do dump
docker compose exec db psql -U aluno -d postgres -c "DROP DATABASE matricula WITH (FORCE);"
docker compose exec db psql -U aluno -d postgres -c "CREATE DATABASE matricula;"
docker compose exec db pg_restore -U aluno -d matricula /tmp/matricula.dump

# 3) conferir
docker compose exec db psql -U aluno -d matricula -c "SELECT count(*) FROM tb_historico;"   # 117.960
```

`DROP DATABASE ... WITH (FORCE)` derruba as conexões abertas (por exemplo, a do
CloudBeaver). Depois, no CloudBeaver, atualize/reconecte a conexão.

## 4. Teste do zero (servidor novo, sem nada)

É o que prova que o backup é de fato reproduzível: destrói **tudo** e reconstrói.

```bash
# 1) destruir contêineres e volumes
docker compose down -v

# 2) subir de novo (o banco "matricula" nasce vazio)
docker compose up -d

# 3) devolver os arquivos para dentro do contêiner novo
docker compose cp ./backups/globais.sql    db:/tmp/globais.sql
docker compose cp ./backups/matricula.dump db:/tmp/matricula.dump

# 4) restaurar primeiro os papéis (globais) e depois o banco
docker compose exec db psql -U aluno -d postgres -f /tmp/globais.sql
docker compose exec db pg_restore -U aluno -d matricula /tmp/matricula.dump

# 5) conferir
docker compose exec db psql -U aluno -d matricula -c "SELECT count(*) FROM tb_matricula;"
```

Mensagens esperadas e inofensivas no passo 4: `role "aluno" already exists`
(o superusuário já foi criado pelo Docker) e, no `pg_restore`, avisos de objetos
que já existem. Se o `pg_restore` terminar com erros sobre outros assuntos,
leia a mensagem antes de seguir.

Depois de restaurar a materialized view, os dados dela vêm junto no dump. Se
quiser garantir que está atualizada:

```bash
docker compose exec db psql -U aluno -d matricula -c "REFRESH MATERIALIZED VIEW mv_indicadores_disciplina;"
```

## 5. Por que esta estratégia (para a defesa)

* **Backup lógico (`pg_dump`)**: arquivo portável, restaura em outro servidor ou
  versão, permite restaurar só uma tabela (`pg_restore -t`). É o adequado para o
  tamanho e para a finalidade acadêmica do projeto.
* **Formato custom (`-Fc`)**: compactado e permite restauração seletiva e
  paralela (`pg_restore -j`). O formato SQL puro (`-Fp`) é legível, mas
  restaura tudo de uma vez.
* **Consistência**: o `pg_dump` roda numa única transação com snapshot, então o
  arquivo é consistente mesmo com o banco em uso.
* **Limite**: o backup lógico só recupera até o instante em que foi feito. Para
  recuperar até um instante qualquer (*point-in-time recovery*), seria preciso
  arquivar o WAL junto com um backup físico (`pg_basebackup`). Em produção,
  combina-se os dois.
* **Papéis são globais**: por isso o `pg_dumpall --globals-only` separado.
