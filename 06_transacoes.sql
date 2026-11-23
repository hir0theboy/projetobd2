-- =====================================================================
-- 06_transacoes.sql  |  Transações e concorrência: a disputa pela última vaga
-- Rode DEPOIS do 02_carga.sql (usa a "turma da disputa", codigo_turma = 99,
-- que tem UMA única vaga em 2026/2).
--
-- COMO USAR (importante!):
--   * A PARTE 0 (criação das funções) pode ser executada como script
--     (Alt + X no CloudBeaver).
--   * Os EXPERIMENTOS (partes 1, 2 e 3) são MANUAIS e precisam de DUAS
--     sessões ao mesmo tempo: abra DOIS editores SQL no CloudBeaver
--     (cada editor usa a sua própria conexão) e chame um de "SESSÃO A" e o
--     outro de "SESSÃO B". Copie cada comando no editor indicado.
--   * Entre um experimento e outro, rode a LIMPEZA (parte 4).
--
-- ALUNOS DO EXPERIMENTO: matrículas 20250001 (sessão A) e 20250002 (sessão B).
--
-- A IDEIA EM UMA FRASE:
--   Dois alunos clicam em "matricular" ao mesmo tempo na turma com 1 vaga.
--   Se a lógica for "olho se tem vaga e depois insiro", as duas sessões
--   olham ANTES de qualquer uma inserir, as duas veem "tem vaga" e as duas
--   inserem: a turma fica com 2 matriculados para 1 vaga (vagas = -1).
--   O banco não impede isso sozinho: não existe nenhuma restrição que
--   compare vagas_turma com o número de matrículas.
-- =====================================================================


-- =====================================================================
-- PARTE 0) FUNÇÕES (rode como script)
-- A função tem o parâmetro p_pausa: um pg_sleep entre "checar a vaga" e
-- "inserir". Isso só existe para ALARGAR a janela da corrida e tornar a
-- anomalia reproduzível na demonstração. Num sistema real a janela é de
-- milissegundos, mas o problema é exatamente o mesmo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- (a) VERSÃO INGÊNUA: checa e depois insere. É a que tem a anomalia.
--     Também é usada na correção por nível de isolamento (SERIALIZABLE),
--     porque nessa correção a lógica não muda: quem muda é a transação.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION matricular_ingenuo(
    p_id_aluno int,
    p_id_turma int,
    p_pausa    numeric DEFAULT 0
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    v_vagas    int;
    v_ocupadas int;
BEGIN
    SELECT vagas_turma INTO v_vagas
    FROM tb_turma
    WHERE id_turma = p_id_turma;

    IF NOT FOUND THEN
        RETURN 'TURMA INEXISTENTE';
    END IF;

    SELECT count(*) INTO v_ocupadas
    FROM tb_matricula
    WHERE id_turma = p_id_turma AND status_matricula;

    IF v_ocupadas >= v_vagas THEN
        RETURN 'SEM VAGA';
    END IF;

    PERFORM pg_sleep(p_pausa::float8);   -- janela da corrida (só para a demo)

    INSERT INTO tb_matricula (id_turma, id_aluno)
    VALUES (p_id_turma, p_id_aluno);

    RETURN 'MATRICULADO';
END $$;

-- ---------------------------------------------------------------------
-- (b) CORREÇÃO 1: BLOQUEIO EXPLÍCITO (pessimista).
--     A primeira instrução trava a linha da turma com FOR UPDATE.
--     Quem chega depois fica ESPERANDO nessa linha até a primeira
--     transação terminar (COMMIT ou ROLLBACK). Só então conta as vagas,
--     e o count enxerga a matrícula que a outra acabou de gravar.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION matricular_com_lock(
    p_id_aluno int,
    p_id_turma int,
    p_pausa    numeric DEFAULT 0
) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    v_vagas    int;
    v_ocupadas int;
BEGIN
    SELECT vagas_turma INTO v_vagas
    FROM tb_turma
    WHERE id_turma = p_id_turma
    FOR UPDATE;                          -- <<< o bloqueio

    IF NOT FOUND THEN
        RETURN 'TURMA INEXISTENTE';
    END IF;

    SELECT count(*) INTO v_ocupadas
    FROM tb_matricula
    WHERE id_turma = p_id_turma AND status_matricula;

    IF v_ocupadas >= v_vagas THEN
        RETURN 'SEM VAGA';
    END IF;

    PERFORM pg_sleep(p_pausa::float8);   -- janela da corrida (só para a demo)

    INSERT INTO tb_matricula (id_turma, id_aluno)
    VALUES (p_id_turma, p_id_aluno);

    RETURN 'MATRICULADO';
END $$;


-- =====================================================================
-- PARTE 1) REPRODUZINDO A ANOMALIA (READ COMMITTED, o nível padrão)
--
-- Passo 0 (qualquer sessão): confirme que a turma está vazia.
--   SELECT * FROM vw_vagas_turma WHERE codigo_turma = 99;
--   -- esperado: vagas_turma = 1, matriculados = 0, vagas_disponiveis = 1
--
-- Passo 1 (SESSÃO A): rode e, SEM esperar terminar, vá para a sessão B.
--   SELECT matricular_ingenuo(
--       (SELECT id_aluno FROM tb_aluno  WHERE matricula_aluno = 20250001),
--       (SELECT id_turma FROM tb_turma  WHERE codigo_turma    = 99),
--       15);
--
-- Passo 2 (SESSÃO B): em até 15 segundos depois do passo 1, rode:
--   SELECT matricular_ingenuo(
--       (SELECT id_aluno FROM tb_aluno  WHERE matricula_aluno = 20250002),
--       (SELECT id_turma FROM tb_turma  WHERE codigo_turma    = 99),
--       15);
--
-- Resultado: as DUAS sessões devolvem 'MATRICULADO'.
--
-- Passo 3 (qualquer sessão): veja o estrago.
--   SELECT * FROM vw_vagas_turma WHERE codigo_turma = 99;
--   -- vagas_turma = 1, matriculados = 2, vagas_disponiveis = -1   <<< ANOMALIA
--
-- POR QUE ACONTECEU: no READ COMMITTED cada comando enxerga apenas o que
-- JÁ FOI GRAVADO (commit) por outros. Quando a sessão B contou as
-- matrículas, a A ainda não tinha inserido nada (estava no pg_sleep), então
-- B viu 0 e achou que havia vaga. É um "check-then-act" sem proteção:
-- entre o CHECK e o ACT, o mundo mudou. Também é chamado de lost update /
-- write skew (duas transações leem o mesmo estado e escrevem em linhas
-- diferentes, e o resultado conjunto viola uma regra que cada uma,
-- isolada, respeitaria).
-- =====================================================================


-- =====================================================================
-- PARTE 2) CORREÇÃO 1: BLOQUEIO EXPLÍCITO (SELECT ... FOR UPDATE)
--
-- Rode a LIMPEZA (parte 4) antes. Mesmos passos, outra função:
--
-- SESSÃO A:
--   SELECT matricular_com_lock(
--       (SELECT id_aluno FROM tb_aluno  WHERE matricula_aluno = 20250001),
--       (SELECT id_turma FROM tb_turma  WHERE codigo_turma    = 99),
--       15);
--
-- SESSÃO B (em até 15 s):
--   SELECT matricular_com_lock(
--       (SELECT id_aluno FROM tb_aluno  WHERE matricula_aluno = 20250002),
--       (SELECT id_turma FROM tb_turma  WHERE codigo_turma    = 99),
--       15);
--
-- Resultado: A devolve 'MATRICULADO'. B FICA ESPERANDO (o editor "trava"
-- por até ~15 s) e, quando A termina, devolve 'SEM VAGA'.
--   SELECT * FROM vw_vagas_turma WHERE codigo_turma = 99;
--   -- matriculados = 1, vagas_disponiveis = 0   <<< CORRETO
--
-- POR QUE FUNCIONA: FOR UPDATE faz a sessão A "dona" da linha da turma até
-- o fim da transação. B não consegue nem começar a conferir as vagas: fica
-- em fila. Quando B finalmente passa, o count (um comando novo, com
-- snapshot novo no READ COMMITTED) já enxerga a matrícula de A.
-- Atenção: o lock é na linha da TURMA (o recurso disputado), não na
-- tabela de matrículas. Alunos entrando em OUTRAS turmas não esperam.
-- =====================================================================


-- =====================================================================
-- PARTE 3) CORREÇÃO 2: NÍVEL DE ISOLAMENTO SERIALIZABLE
--
-- Rode a LIMPEZA (parte 4) antes. Aqui usamos a função INGÊNUA (a lógica
-- continua sem lock); o que muda é a transação, que agora é SERIALIZABLE.
--
-- SESSÃO A:
--   BEGIN ISOLATION LEVEL SERIALIZABLE;
--   SELECT matricular_ingenuo(
--       (SELECT id_aluno FROM tb_aluno  WHERE matricula_aluno = 20250001),
--       (SELECT id_turma FROM tb_turma  WHERE codigo_turma    = 99),
--       15);
--   COMMIT;
--
-- SESSÃO B (em até 15 s depois do BEGIN de A):
--   BEGIN ISOLATION LEVEL SERIALIZABLE;
--   SELECT matricular_ingenuo(
--       (SELECT id_aluno FROM tb_aluno  WHERE matricula_aluno = 20250002),
--       (SELECT id_turma FROM tb_turma  WHERE codigo_turma    = 99),
--       15);
--   COMMIT;
--
-- Resultado: as duas conseguem rodar, mas UMA delas falha (no INSERT ou no
-- COMMIT) com:
--   ERROR: could not serialize access due to read/write dependencies
--          among transactions            (SQLSTATE 40001)
-- A sessão que falhou precisa dar ROLLBACK e TENTAR DE NOVO (retentativa):
--   ROLLBACK;
--   BEGIN ISOLATION LEVEL SERIALIZABLE;
--   SELECT matricular_ingenuo(<aluno que falhou>, <turma 99>, 0);
--   COMMIT;
-- Na segunda tentativa a função devolve 'SEM VAGA'.
--   SELECT * FROM vw_vagas_turma WHERE codigo_turma = 99;
--   -- matriculados = 1, vagas_disponiveis = 0   <<< CORRETO
--
-- POR QUE FUNCIONA: no SERIALIZABLE o PostgreSQL (SSI) rastreia o que cada
-- transação LEU e o que ESCREVEU. A leu "as matrículas da turma 99" e B
-- inseriu uma; B também leu o mesmo conjunto e A inseriu outra. Isso forma
-- um ciclo de dependências: não existe nenhuma ordem serial (A depois de B
-- ou B depois de A) que produza aquele resultado. O banco aborta uma das
-- duas para garantir que o resultado seja equivalente a uma execução uma
-- depois da outra.
-- IMPORTANTE: REPEATABLE READ NÃO resolveria. Ele dá um snapshot fixo, mas
-- as duas sessões continuariam vendo "0 matriculados" e inserindo: é
-- exatamente o write skew, que só o SERIALIZABLE detecta.
-- A retentativa é responsabilidade da APLICAÇÃO (do cliente): o banco só
-- avisa com o erro 40001. Dentro de uma função PL/pgSQL não dá para
-- trocar o nível de isolamento nem repetir uma transação abortada.
-- =====================================================================


-- =====================================================================
-- VARIANTE DETERMINÍSTICA (sem depender do tempo)
-- Se, no experimento com pausa, as transações não chegarem a se sobrepor
-- (a primeira termina antes de a segunda ler), o conflito não acontece.
-- Para forçar a sobreposição, intercale os passos na mão, UM comando por
-- vez, na ordem numerada (pausa 0). Serve para as três funções/níveis.
--   1) A: BEGIN ISOLATION LEVEL SERIALIZABLE;
--   2) A: SELECT matricular_ingenuo(<aluno 20250001>, <turma 99>, 0);
--   3) B: BEGIN ISOLATION LEVEL SERIALIZABLE;
--   4) B: SELECT matricular_ingenuo(<aluno 20250002>, <turma 99>, 0);
--   5) A: COMMIT;
--   6) B: COMMIT;      -- um dos COMMITs (ou o passo 4) falha com 40001
-- A sessão que falhou: ROLLBACK; e repetir os passos dela -> 'SEM VAGA'.
-- =====================================================================


-- =====================================================================
-- COMPARAÇÃO FUNDAMENTADA (para o relatório e a defesa)
--
-- | Aspecto             | FOR UPDATE (bloqueio)        | SERIALIZABLE            |
-- |---------------------|------------------------------|-------------------------|
-- | Estratégia          | Pessimista: bloqueia antes   | Otimista: roda e, se há |
-- |                     | de conferir                  | conflito, aborta        |
-- | Quem espera         | O segundo fica em FILA até   | Ninguém espera; um é    |
-- |                     | o primeiro terminar          | ABORTADO                |
-- | Retentativa         | Não precisa (só espera)      | Obrigatória (erro 40001)|
-- | Contenção           | Alta na turma disputada;     | Baixa quando há pouco   |
-- |                     | serializa todos naquela linha| conflito; sob muita     |
-- |                     |                              | disputa, muitas         |
-- |                     |                              | retentativas            |
-- | Custo               | Locks de linha (baratos);    | Rastreamento de leituras|
-- |                     | risco de espera e deadlock   | (SIREAD) em TODA a      |
-- |                     | se mal ordenados             | transação; pode ter     |
-- |                     |                              | falso positivo          |
-- | Onde a regra mora   | Dentro da lógica (a função   | Na configuração da      |
-- |                     | precisa lembrar do FOR       | transação (a lógica     |
-- |                     | UPDATE)                      | pode ficar ingênua)     |
-- | Melhor quando       | Recurso quente e conhecido   | Regras complexas que    |
-- |                     | (a vaga de UMA turma)        | envolvem várias tabelas |
-- |                     |                              | e baixa disputa         |
--
-- Para a "última vaga", o FOR UPDATE é a escolha mais simples e previsível:
-- o recurso disputado é conhecido (a linha da turma). O SERIALIZABLE é mais
-- geral (protege invariantes que você nem identificou), mas cobra o preço
-- da retentativa.
-- =====================================================================


-- =====================================================================
-- PARTE 4) LIMPEZA (rode entre um experimento e outro)
-- Remove as matrículas feitas na turma da disputa.
-- =====================================================================
-- DELETE FROM tb_matricula
-- WHERE id_turma = (SELECT id_turma FROM tb_turma WHERE codigo_turma = 99);

-- Conferência rápida do estado da turma da disputa:
-- SELECT * FROM vw_vagas_turma WHERE codigo_turma = 99;
