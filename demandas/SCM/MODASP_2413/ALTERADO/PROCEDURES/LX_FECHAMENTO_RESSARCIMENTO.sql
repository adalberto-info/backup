CREATE PROCEDURE [dbo].[LX_FECHAMENTO_RESSARCIMENTO] @COD_FECHAMENTO AS CHAR(8), @EMPRESA AS INT  
AS  

	BEGIN TRY 
	 
	-------------------------------------------------------------------------------------------------------------------------------------------------  
	-- Procedure para gera��o das tabelas CONTROLE_ENT_RESSARCIMENTO e CONTROLE_SAI_RESSARCIMENTO                                                  --  
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- 04/12/2019 - Adalberto (WAFX) - #0# - MODASP-2413   - Cria��o da stored procedure LX_FECHAMENTO_RESSARCIMENTO.                              --
	-------------------------------------------------------------------------------------------------------------------------------------------------  
	 
	SET NOCOUNT ON  
	 
	DECLARE @UTILIZA_SALDO_ANTERIOR AS BIT, @COD_FECHAMENTO_ANTERIOR AS CHAR(8), @DATA_FECHAMENTO AS DATETIME, @ERRMSG  VARCHAR(255)
	DECLARE @DT_INI_RESS DATETIME, @DT_FIM_RESS DATETIME, @DT_INI_ANTERIOR DATETIME, @DT_FIM_ANTERIOR DATETIME
    DECLARE @PCOD_FILIAL, @PCOD_MATRIZ_CONTABIL, @RESSARCIMENTO_POR_FILIAL

	SELECT @UTILIZA_SALDO_ANTERIOR = A.UTILIZA_SALDO_ANTERIOR,  
		   @COD_FECHAMENTO_ANTERIOR = A.COD_FECHAMENTO_ANTERIOR, 
		   @DT_INI_RESS = A.DATA_INICIAL,
		   @DT_FIM_RESS = A.DATA_FIM
	FROM DADOS_FECHAMENTO_RESSARCIMENTO AS A (NOLOCK)  
	WHERE A.COD_FECHAMENTO = @COD_FECHAMENTO  
	
	SELECT 	@DT_INI_ANTERIOR = DADOS_FECHAMENTO_RESSARCIMENTO.DATA_INICIAL,
            @DT_FIM_ANTERIOR = DADOS_FECHAMENTO_RESSARCIMENTO.DATA_FINAL	
	FROM DADOS_FECHAMENTO_RESSARCIMENTO 
	WHERE COD_FECHAMENTO=@COD_FECHAMENTO_ANTERIOR 


	------------------------------------------------------------------------------------------------------------------------------------------------
	-- VERIFICA SE EXISTE UMA PROCEDURE CUSTOMIZADA DO CLIENTE PARA FECHAMENTO DO RESSARCIMENTO
	------------------------------------------------------------------------------------------------------------------------------------------------
	IF EXISTS( SELECT * FROM SYSOBJECTS WHERE NAME = 'LX_FECHAMENTO_RESSARCIMENTO_OE_INICIO' )
		EXECUTE LX_FECHAMENTO_RESSARCIMENTO_OE_INICIO @COD_FECHAMENTO, @EMPRESA
	------------------------------------------------------------------------------------------------------------------------------------------------

	-------------------------------------------------------------------------------------------------------------------------------------------------  
	-- Exclui os registros antigos das tabelas filhas.  
	-------------------------------------------------------------------------------------------------------------------------------------------------  
	DELETE CONTROLE_ENT_RESSARCIMENTO  
	WHERE COD_FECHAMENTO = @COD_FECHAMENTO  
	 
	DELETE CONTROLE_SAI_RESSARCIMENTO
	WHERE COD_FECHAMENTO = @COD_FECHAMENTO  
	 
	DELETE CONTROLE_SALDO_RESSARCIMENTO
	WHERE COD_FECHAMENTO = @COD_FECHAMENTO  

	-------------------------------------------------------------------------------------------------------------------------------------------------  
	-- Selecionando as notas fiscais de entrada [tabela CONTROLE_ENT_RESSARCIMENTO]
	-------------------------------------------------------------------------------------------------------------------------------------------------  

	DECLARE @TMP_ENTRADA TABLE ([EMPRESA] [INT] ,
								[FILIAL] [varchar](25) ,
								[NOME_CLIFOR] [varchar](25) ,
								[NF_ENTRADA] [char](15) ,
								[SERIE_NF] [varchar](6) ,
								[CHAVE_NFE] [varchar](44) ,
								[RECEBIMENTO] [datetime] ,
								[VALOR_TOTAL] [numeric](14,2) ,
								[ITEM] [char](12) ,
								[COR_ITEM] [char](10) ,
								[TAMANHO] [varchar](8) ,
								[QTDE_ENTRADA] [numeric](9,3) ,
								[ALIQUOTA] [numeric](14,2) ,
								[BASE_ICMS_ST] [numeric](14,2) ,
								[ICMS_EFETIVO] [numeric](14,2) ,
								[ICMS_PRESUMIDO] [numeric](14,2) ,
								[BASE_ICMS_PRESUMIDO] [numeric](14,2) ,
								[VALOR_ISENTO] [numeric](14,2) ,
								[SEQ_ITEM_SUBTITUTO] [char](4) ,
								[CHAVE_NFE_SUBSTITUTO] [varchar](44) ,
								[CODIGO_FISCAL_OPERACAO] [char](4) ,
								[NATUREZA] [char](15) ,
								[SALDO_NF_ENTRADA] [numeric](9,3)) 

	-- Selecionando as notas de entrada do per�odo selecionado...		
	IF @RESSARCIMENTO_POR_FILIAL = 1
		BEGIN 
			insert into @TMP_ENTRADA (EMPRESA, FILIAL, NOME_CLIFOR, NF_ENTRADA, SERIE_NF, CHAVE_NFE, RECEBIMENTO,
									  VALOR_TOTAL, ITEM, COR_ITEM, TAMANHO, QTDE_ENTRADA, ALIQUOTA, BASE_ICMS_ST,
									  ICMS_EFETIVO, ICMS_PRESUMIDO, BASE_ICMS_PRESUMIDO, VALOR_ISENTO,
									  SEQ_ITEM_SUBTITUTO, CHAVE_NFE_SUBSTITUTO, CODIGO_FISCAL_OPERACAO,
									  NATUREZA, SALDO_NF_ENTRADA) 
			SELECT C.EMPRESA, A.FILIAL, A.NOME_CLIFOR, A.NF_ENTRADA, A.SERIE_NF, A.CHAVE_NFE, A.RECEBIMENTO, 
				   A.VALOR_TOTAL, B.CODIGO_ITEM, LEFT(ISNULL(B.REFERENCIA_ITEM, ''),10) AS COR_ITEM, 
				   B.SUB_ITEM_TAMANHO AS TAMANHO, B.QTDE_ITEM, D.ALIQUOTA, D.BASE_ICMS_SUBSTITUTO,
				   F.VALOR_IMPOSTO AS ICMS_EFETIVO, D.ICMS_PRESUMIDO, D.BASE_ICMS_SUBSTITUTO AS BASE_ICMS_PRESUMIDO, 
				   CASE WHEN G.TRIBUT_ICMS IN ('40','41') THEN B.VALOR_ITEM ELSE 0.00 END AS VALOR_ISENTO, 
				   B.SEQ_ITEM_SUBSTITUTO, B.CHAVE_NFE_SUBSTITUTO, B.CODIGO_FISCAL_OPERACAO, A.NATUREZA, 
				   0 AS SALDO_NF_ENTRADA
			FROM ENTRADAS A 
			INNER JOIN ENTRADAS_ITEM B
			ON A.NF_ENTRADA = B.NF_ENTRADA 
			AND A.SERIE_NF_ENTRADA = B.SERIE_NF_ENTRADA
			AND A.NOME_CLIFOR = B.NOME_CLIFOR
			INNER JOIN FILIAIS C 
			ON A.FILIAL = C.FILIAL 
			INNER JOIN ENTRADAS_IMPOSTO D 
			ON B.NF_ENTRADA = D.NF_ENTRADA 
			AND B.SERIE_NF_ENTRADA = D.SERIE_NF_ENTRADA 
			AND B.NOME_CLIFOR = D.NOME_CLIFOR
			AND B.ITEM_IMPRESSAO = D.ITEM_IMPRESSAO  
			AND B.SUB_ITEM_TAMANHO = D.SUB_ITEM_TAMANHO
			INNER JOIN PRODUTOS_UF_ICMS E 
			ON B.CODIGO_ITEM = E.PRODUTO
			AND E.IS_ICMS_SUBSTITUTO = 1
			INNER JOIN ENTRADAS_IMPOSTO F
			ON B.NF_ENTRADA = F.NF_ENTRADA 
			AND B.SERIE_NF_ENTRADA = F.SERIE_NF_ENTRADA 
			AND B.NOME_CLIFOR = F.NOME_CLIFOR
			AND F.ID_IMPOSTO = 1
			LEFT JOIN CTB_EXCECAO_IMPOSTO G
			ON B.ID_EXCECAO_IMPOSTO = G.ID_EXCECAO_IMPOSTO
			AND G.TRIBUT_ICMS IN ('40','41')
			INNER JOIN RESSARCIMENTO_FILIAIS RF 
			ON RF.COD_FILIAL = A.FILIAL
			WHERE B.RECEBIMENTO BETWEEN @DT_INI_RESS AND @DT_FIM_RESS
			AND RF.COD_FECHAMENTO = @COD_FECHAMENTO 
		
		END
	ELSE
		BEGIN
			INSERT INTO @TMP_ENTRADA (EMPRESA, FILIAL, NOME_CLIFOR, NF_ENTRADA, SERIE_NF, CHAVE_NFE, RECEBIMENTO,
									  VALOR_TOTAL, ITEM, COR_ITEM, TAMANHO, QTDE_ENTRADA, ALIQUOTA, BASE_ICMS_ST,
									  ICMS_EFETIVO, ICMS_PRESUMIDO, BASE_ICMS_PRESUMIDO, VALOR_ISENTO,
									  SEQ_ITEM_SUBTITUTO, CHAVE_NFE_SUBSTITUTO, CODIGO_FISCAL_OPERACAO,
									  NATUREZA, SALDO_NF_ENTRADA) 
			SELECT C.EMPRESA, A.FILIAL, A.NOME_CLIFOR, A.NF_ENTRADA, A.SERIE_NF, A.CHAVE_NFE, A.RECEBIMENTO, 
				   A.VALOR_TOTAL, B.CODIGO_ITEM, LEFT(ISNULL(B.REFERENCIA_ITEM, ''),10) AS COR_ITEM, 
				   B.SUB_ITEM_TAMANHO AS TAMANHO, B.QTDE_ITEM, D.ALIQUOTA, D.BASE_ICMS_SUBSTITUTO,
				   F.VALOR_IMPOSTO AS ICMS_EFETIVO, D.ICMS_PRESUMIDO, D.BASE_ICMS_SUBSTITUTO AS BASE_ICMS_PRESUMIDO, 
				   CASE WHEN G.TRIBUT_ICMS IN ('40','41') THEN B.VALOR_ITEM ELSE 0.00 END AS VALOR_ISENTO, 
				   B.SEQ_ITEM_SUBSTITUTO, B.CHAVE_NFE_SUBSTITUTO, B.CODIGO_FISCAL_OPERACAO, A.NATUREZA, 
				   0 AS SALDO_NF_ENTRADA
			FROM ENTRADAS A 
			INNER JOIN ENTRADAS_ITEM B
			ON A.NF_ENTRADA = B.NF_ENTRADA 
			AND A.SERIE_NF_ENTRADA = B.SERIE_NF_ENTRADA
			AND A.NOME_CLIFOR = B.NOME_CLIFOR
			INNER JOIN FILIAIS C 
			ON A.FILIAL = C.FILIAL 
			INNER JOIN ENTRADAS_IMPOSTO D 
			ON B.NF_ENTRADA = D.NF_ENTRADA 
			AND B.SERIE_NF_ENTRADA = D.SERIE_NF_ENTRADA 
			AND B.NOME_CLIFOR = D.NOME_CLIFOR
			AND B.ITEM_IMPRESSAO = D.ITEM_IMPRESSAO  
			AND B.SUB_ITEM_TAMANHO = D.SUB_ITEM_TAMANHO
			INNER JOIN CADASTRO_CLI_FOR H
			ON A.FILIAL = H.NOME_CLIFOR
			INNER JOIN PRODUTOS_UF_ICMS E 
			ON B.CODIGO_ITEM = E.PRODUTO
			AND E.UF = H.UF
			AND E.IS_ICMS_SUBSTITUTO = 1
			INNER JOIN ENTRADAS_IMPOSTO F
			ON B.NF_ENTRADA = F.NF_ENTRADA 
			AND B.SERIE_NF_ENTRADA = F.SERIE_NF_ENTRADA 
			AND B.NOME_CLIFOR = F.NOME_CLIFOR
			AND F.ID_IMPOSTO = 1
			LEFT JOIN CTB_EXCECAO_IMPOSTO G
			ON B.ID_EXCECAO_IMPOSTO = G.ID_EXCECAO_IMPOSTO
			AND G.TRIBUT_ICMS IN ('40','41')
			WHERE B.RECEBIMENTO BETWEEN @DT_INI_RESS AND @DT_FIM_RESS
			AND C.EMPRESA = @EMPRESA
		END


	-------------------------------------------------------------------------------------------------------------------------------------------------  
	-- Selecionando as notas fiscais de saida [tabela CONTROLE_SAI_RESSARCIMENTO]
	-------------------------------------------------------------------------------------------------------------------------------------------------  

	DECLARE @TMP_SAIDA TABLE ([EMPRESA] [INT] ,
						  	  [FILIAL] [varchar](25) ,
							  [NOME_CLIFOR] [varchar](25) ,
							  [NF_SAIDA] [char](15) ,
							  [SERIE_NF] [varchar](6) ,
							  [CHAVE_NFE] [varchar](44) ,
							  [EMISSAO] [datetime] ,
							  [VALOR_TOTAL] [numeric](14,2) ,
							  [ITEM] [char](12) ,
							  [COR_ITEM] [char](10) ,
							  [TAMANHO] [varchar](8) ,
							  [QTDE_VENDIDA] [numeric](9,3) ,
							  [ALIQUOTA] [numeric](14,2) ,
							  [BASE_ICMS_ST] [numeric](14,2) ,
							  [ICMS_EFETIVO] [numeric](14,2) ,
							  [ICMS_PRESUMIDO] [numeric](14,2) ,
							  [BASE_ICMS_PRESUMIDO] [numeric](14,2) ,
							  [VALOR_ISENTO] [numeric](14,2) ,
							  [SEQ_ITEM_SUBTITUTO] [char](4) ,
							  [CHAVE_NFE_SUBSTITUTO] [varchar](44) ,
							  [CODIGO_FISCAL_OPERACAO] [char](4) ,
							  [NATUREZA] [char](15) ,
							  [SALDO_NF_ENTRADA] [numeric](9,3),
							  [INDICA_CONSUMIDOR_FINAL] [bit]),
							  [CODIGO_FISCAL_OPERACAO] [char](4),
							  [NF_ENTRADA_RELACIONADA] [char](15),
							  [SERIE_NF_RELACIONADA] [varchar](6) NOT NULL DEFAULT '',
							  [NOME_CLIFOR_RELACIONADA] [varchar](25),
							  [RECEBIMENTO_RELACIONADA] [datetime],
							  [QTDE] [numeric](9,3),
							  [ICMS_PRESUMIDO] [numeric](14,2),
							  [CHAVE_NFE_SUBSTITUTO] [varchar](44),
							  [SEQ_ITEM_SUBSTITUTO] [char](4),
							  [COD_FECHAMENTO] [char](8))
							  
	INSERT INTO @TMP_SAIDA (EMPRESA, FILIAL, NOME_CLIFOR, NF_SAIDA, SERIE_NF, CHAVE_NFE, EMISSAO, VALOR_TOTAL, ITEM,
							COR_ITEM, TAMANHO, QTDE_VENDIDA, ALIQUOTA, BASE_ICMS_ST, ICMS_EFETIVO, ICMS_PRESUMIDO,
							BASE_ICMS_PRESUMIDO, VALOR_ISENTO, SEQ_ITEM_SUBTITUTO, CHAVE_NFE_SUBSTITUTO,
							CODIGO_FISCAL_OPERACAO, NATUREZA, SALDO_NF_ENTRADA, INDICA_CONSUMIDOR_FINAL, CODIGO_FISCAL_OPERACAO,
							NF_ENTRADA_RELACIONADA, SERIE_NF_RELACIONADA, NOME_CLIFOR_RELACIONADA, RECEBIMENTO_RELACIONADA,
							QTDE, ICMS_PRESUMIDO, CHAVE_NFE_SUBSTITUTO, SEQ_ITEM_SUBSTITUTO, COD_FECHAMENTO)
	SELECT C.EMPRESA, A.FILIAL, A.NOME_CLIFOR, A.NF_SAIDA, A.SERIE_NF, A.CHAVE_NFE, A.EMISSAO, A.VALOR_TOTAL, B.ITEM_NFE,
           LEFT(ISNULL(B.REFERENCIA_ITEM, ''),10) AS COR_ITEM, B.SUB_ITEM_TAMANHO AS TAMANHO, B.QTDE_ITEM, D.ALIQUOTA,
           D.BASE_ICMS_ST, 		   

	
	FROM FATURAMENTO A
	INNER JOIN FATURAMENTO_ITEM B
	ON A.NF_SAIDA = B.NF_SAIDA
    AND A.SERIE_NF = B.SERIE_NF
    AND A.FILIAL = B.FILIAL
    INNER JOIN FILIAIS C 
    ON A.FILIAL = C.FILIAL
	INNER JOIN FATURAMENTO_IMPOSTO D
	ON B.FILIAL = D.FILIAL 
	AND B.NF_SAIDA = D.NF_SAIDA 
	AND B.SERIE_NF = D.SERIE_NF 
	AND B.ITEM_IMPRESSAO = D.ITEM_IMPRESSAO 
	AND B.SUB_ITEM_TAMANHO = D.SUB_ITEM_TAMANHO
	INNER JOIN CADASTRO_CLI_FOR E
	ON A.FILIAL = E.NOME_CLIFOR
	INNER JOIN PRODUTOS_UF_ICMS F 
	AND B.CODIGO_ITEM = F.PRODUTO
	AND F.UF = E.UF
	AND F.IS_ICMS_SUBSTITUTO = 1
	

	-------------------------------------------------------------------------------------------------------------------------------------------------  
	-- Gerando o Fechamento do Ressarcimento [tabela CONTROLE_SALDO_RESSARCIMENTO]
	-------------------------------------------------------------------------------------------------------------------------------------------------  


	-------------------------------------------------------------------------------------------------------------------------------------------------  
	 
	UPDATE DADOS_FECHAMENTO_RESSARCIMENTO  
	SET DATA_GERACAO = CONVERT(DATETIME, CONVERT(CHAR(10), GETDATE(), 112))  
	WHERE COD_FECHAMENTO = @COD_FECHAMENTO  

	-------------------------------------------------------------------------------------------------------------------------------------------------	
	  
	SET NOCOUNT OFF

	------------------------------------------------------------------------------------------------------------------------------------------------
	-- VERIFICA SE EXISTE UMA PROCEDURE CUSTOMIZADA DO CLIENTE PARA FECHAMENTO DE RESSARCIMENTO
	------------------------------------------------------------------------------------------------------------------------------------------------
	IF EXISTS( SELECT * FROM SYSOBJECTS WHERE NAME = 'LX_FECHAMENTO_RESSARCIMENTO_OE_FINAL' )
		EXECUTE LX_FECHAMENTO_RESSARCIMENTO_OE_FINAL @COD_FECHAMENTO, @EMPRESA
	------------------------------------------------------------------------------------------------------------------------------------------------

 END TRY 

 BEGIN CATCH 

    WHILE @@TRANCOUNT != 0 
    BEGIN 
        IF ( XACT_STATE() ) = 1 
            BEGIN 
                COMMIT TRANSACTION 
            END 
        ELSE 
            BEGIN 
                ROLLBACK TRANSACTION 
            END 
    END 

	SET @ERRMSG = ERROR_MESSAGE()

    SET NOCOUNT OFF	
	SET ANSI_WARNINGS ON

	INSERT INTO FECHAMENTO_RESSARCIMENTO_ERRO(COD_FECHAMENTO,ERRO,DATA)  SELECT @COD_FECHAMENTO,@ERRMSG,GETDATE() 

	RAISERROR (@ERRMSG, 16,1)

  END CATCH 



