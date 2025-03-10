
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE TABLE IF NOT EXISTS clientes (
	id SERIAL PRIMARY KEY,
	limite INTEGER NOT NULL,
  saldo INTEGER NOT NULL
);

CREATE INDEX idx_clientes ON clientes USING HASH(id);

CREATE TABLE IF NOT EXISTS transacoes (
	id SERIAL PRIMARY KEY,
	cliente_id INTEGER NOT NULL,
	valor INTEGER NOT NULL,
	tipo CHAR(1) NOT NULL,
	descricao VARCHAR(10) NOT NULL,
	realizada_em TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT fk_clientes_transacoes_id
		FOREIGN KEY (cliente_id) REFERENCES clientes(id)
    ON DELETE CASCADE
);

CREATE INDEX idx_transacao ON transacoes USING btree(cliente_id);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM clientes) THEN
        INSERT INTO clientes (limite, saldo)
        VALUES
            (1000 * 100, 0),
            (800 * 100, 0),
            (10000 * 100, 0),
            (100000 * 100, 0),
            (5000 * 100, 0);
    END IF;
END;
$$;



CREATE OR REPLACE FUNCTION extrato(_cliente_id INTEGER)
RETURNS JSON AS $$
DECLARE
    saldo JSON;
    ultimas_transacoes JSON;
BEGIN
    SELECT
        json_build_object(
            'total', c.saldo,
            'data_extrato', NOW(),
            'limite', c.limite
        )
    INTO
        saldo
    FROM
        clientes c
    WHERE
        c.id = _cliente_id;

    SELECT
        CASE
            WHEN COUNT(*) > 0 THEN json_agg(json_build_object(
                'valor', t.valor,
                'tipo', t.tipo,
                'descricao', t.descricao,
                'realizada_em', t.realizada_em
            ))
            ELSE '[]'::JSON
        END
    INTO
        ultimas_transacoes
    FROM (
        SELECT
            valor,
            tipo,
            descricao,
            realizada_em
        FROM
            transacoes
        WHERE
            cliente_id = _cliente_id
        ORDER BY
            id DESC
        LIMIT 10
    ) t;

    RETURN json_build_object(
        'saldo', saldo,
        'ultimas_transacoes', ultimas_transacoes
    );
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION transacao(
    _cliente_id INTEGER,
    _valor INTEGER,
    _tipo CHAR,
    _descricao VARCHAR(10),
    OUT codigo_erro SMALLINT,
    OUT resultado JSON
)
RETURNS record AS
$$
DECLARE
    _limite INTEGER;
    _saldo INTEGER;
BEGIN
  BEGIN
    SELECT limite, saldo INTO _limite, _saldo
    FROM clientes
    WHERE id = _cliente_id
    FOR UPDATE;

    IF NOT FOUND THEN
        codigo_erro := 1;
        resultado := NULL;
        RETURN;
    ELSE
        IF _tipo = 'c' THEN
            UPDATE clientes 
            SET saldo = _saldo + _valor 
            WHERE id = _cliente_id 
            RETURNING json_build_object('limite', limite, 'saldo', saldo) INTO resultado;
            INSERT INTO transacoes(cliente_id, valor, tipo, descricao)
            VALUES (_cliente_id, _valor, _tipo, _descricao);
            RETURN;
        ELSEIF _tipo = 'd' AND _saldo - _valor >= -_limite THEN
            UPDATE clientes
            SET saldo = _saldo - _valor
            WHERE id = _cliente_id
            RETURNING json_build_object('limite', limite, 'saldo', saldo) INTO resultado;
            INSERT INTO transacoes(cliente_id, valor, tipo, descricao)
            VALUES (_cliente_id, _valor, _tipo, _descricao);
            RETURN;
        ELSE
            codigo_erro := 2;
            resultado := NULL;
            RETURN;
        END IF;
    END IF;
  END;
END;
$$
LANGUAGE plpgsql;
