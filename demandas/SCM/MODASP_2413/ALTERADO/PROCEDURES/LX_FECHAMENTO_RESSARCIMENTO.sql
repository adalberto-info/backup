CREATE PROCEDURE [dbo].[LX_FECHAMENTO_RESSARCIMENTO] @COD_FECHAMENTO AS CHAR(8), @EMPRESA AS INT  
AS  

	BEGIN TRY 
	 
	-------------------------------------------------------------------------------------------------------------------------------------------------  
	-- Procedure para geração das tabelas CONTROLE_ENT_RESSARCIMENTO e CONTROLE_SAI_RESSARCIMENTO                                                  --  
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- 04/12/2019 - Adalberto (WAFX) - #0# - MODASP-2413   - Criação da stored procedure LX_FECHAMENTO_RESSARCIMENTO.                              --
	-------------------------------------------------------------------------------------------------------------------------------------------------  
	 
	SET NOCOUNT ON  
	 
	DECLARE @UTILIZA_SALDO_ANTERIOR AS BIT, @COD_FECHAMENTO_ANTERIOR AS CHAR(8), @DATA_FECHAMENTO AS DATETIME, @ERRMSG  VARCHAR(255)
	DECLARE @DT_INI_RESS DATETIME, @DT_FIM_RESS DATETIME, @DT_INI_ANTERIOR DATETIME, @DT_FIM_ANTERIOR DATETIME
    DECLARE @PCOD_FILIAL CHAR(6), @PCOD_MATRIZ_CONTABIL CHAR(6)
	DECLARE @COD_FILIAL [CHAR](06), @NF_SAIDA [CHAR](15), @SERIE_NF [CHAR](6), @ITEM [CHAR](12), @TAMANHO [VARCHAR](8), @QTDE_VENDIDA [NUMERIC](12,4)
	DECLARE @COR_ITEM [CHAR](10), @SEQ [NUMERIC](3), @SEQ_AUX [NUMERIC](3)
	DECLARE @NF_ENTRADA [CHAR](15), @SERIE_NF_ENTRADA [CHAR](6), @QTDE_ENTRADA [NUMERIC](12,4), @QTDE_ENTRADA_SALDO [NUMERIC](12,4), @QTDE_SAIDA_SALDO [NUMERIC](12,4)
	DECLARE @NOME_CLIFOR_ENTRADA [VARCHAR](25), @RECEBIMENTO [DATETIME], @QTDE [NUMERIC](12,4), @CHAVE_NFE_SUBSTITUTO [VARCHAR](44), @SEQ_ITEM_SUBSTITUTO [CHAR](4)
	DECLARE @IS_FINALIZOU_SAIDA [BIT], @IS_ACHOU_NF_ENTRADA [BIT], @ATUALIZA_SAIDA [BIT]

	IF EXISTS (SELECT 1 FROM DADOS_FECHAMENTO_RESSARCIMENTO A WHERE A.COD_FECHAMENTO = @COD_FECHAMENTO) 
		BEGIN
		-- Verifica se o Código de fechamento ressarcimento está sendo utilizado como saldo anterior de outro fechamento... 
		IF EXISTS (SELECT a.COD_FECHAMENTO, A.UTILIZA_SALDO_ANTERIOR, A.COD_FECHAMENTO_ANTERIOR
					FROM DADOS_FECHAMENTO_RESSARCIMENTO A 
					WHERE A.UTILIZA_SALDO_ANTERIOR = 1 
					AND A.COD_FECHAMENTO_ANTERIOR = @COD_FECHAMENTO) 
			BEGIN
				SELECT 'Este Fechamento de Ressarcimento está sendo utilizado como saldo inicial de outro Fechamento. Não pode ser Processado!'

				SET @ERRMSG = 'Este Fechamento de Ressarcimento está sendo utilizado como saldo inicial de outro Fechamento. Não pode ser Processado!'
				INSERT INTO FECHAMENTO_RESSARCIMENTO_ERRO(COD_FECHAMENTO,ERRO,DATA)  SELECT @COD_FECHAMENTO,@ERRMSG,GETDATE() 

			END
		ELSE
			BEGIN


			SELECT @UTILIZA_SALDO_ANTERIOR = A.UTILIZA_SALDO_ANTERIOR,  
				   @COD_FECHAMENTO_ANTERIOR = A.COD_FECHAMENTO_ANTERIOR, 
				   @DT_INI_RESS = A.DATA_INICIAL,
				   @DT_FIM_RESS = A.DATA_FINAL
			FROM DADOS_FECHAMENTO_RESSARCIMENTO AS A (NOLOCK)  
			WHERE A.COD_FECHAMENTO = @COD_FECHAMENTO  

			IF @UTILIZA_SALDO_ANTERIOR = 1 AND ISNULL(@COD_FECHAMENTO_ANTERIOR,'') <> ''
				BEGIN	
				SELECT 	@DT_INI_ANTERIOR = DADOS_FECHAMENTO_RESSARCIMENTO.DATA_INICIAL,
						@DT_FIM_ANTERIOR = DADOS_FECHAMENTO_RESSARCIMENTO.DATA_FINAL	
				FROM DADOS_FECHAMENTO_RESSARCIMENTO 
				WHERE COD_FECHAMENTO=@COD_FECHAMENTO_ANTERIOR 
				END
				
			IF EXISTS (SELECT 1 FROM RESSARCIMENTO_FILIAIS A WHERE A.COD_FECHAMENTO = @COD_FECHAMENTO)		
				BEGIN
				-----------------------------------------------------------------------------------------------------------------------------------------------
				-- VERIFICA SE EXISTE UMA PROCEDURE CUSTOMIZADA DO CLIENTE PARA FECHAMENTO DO RESSARCIMENTO				-----------------------------------------------------------------------------------------------------------------------------------------------
				IF EXISTS( SELECT * FROM SYSOBJECTS WHERE NAME = 'LX_FECHAMENTO_RESSARCIMENTO_OE_INICIO' )
					EXECUTE LX_FECHAMENTO_RESSARCIMENTO_OE_INICIO @COD_FECHAMENTO, @EMPRESA
				-----------------------------------------------------------------------------------------------------------------------------------------------
				-----------------------------------------------------------------------------------------------------------------------------------------------
				-- Exclui os registros antigos das tabelas filhas.  
			    -----------------------------------------------------------------------------------------------------------------------------------------------
			    DELETE FROM CONTROLE_ENT_RESSARCIMENTO  
				WHERE COD_FECHAMENTO = @COD_FECHAMENTO  
				 
				DELETE FROM CONTROLE_SAI_RESSARCIMENTO
				WHERE COD_FECHAMENTO = @COD_FECHAMENTO  
				 
				DELETE FROM CONTROLE_SALDO_RESSARCIMENTO
				WHERE COD_FECHAMENTO = @COD_FECHAMENTO  

				-----------------------------------------------------------------------------------------------------------------------------------------------
				-- Selecionando as notas fiscais de saida [tabela CONTROLE_SAI_RESSARCIMENTO]
				-----------------------------------------------------------------------------------------------------------------------------------------------

				-- tabela temporária de CONTROLE_SAI_RESSARCIMENTO
				DECLARE @TMP_SAIDA TABLE ([EMPRESA] [INT] ,
										  [COD_FILIAL] [char](06),
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
										  [ALIQUOTA] [numeric](8,5) ,
										  [BASE_ICMS_ST] [numeric](14,2) ,
										  [ICMS_EFETIVO] [numeric](14,2) ,
										  [ICMS_PRESUMIDO] [numeric](14,2) ,
										  [BASE_ICMS_PRESUMIDO] [numeric](14,2) ,
										  [VALOR_ISENTO] [numeric](14,2) ,
										  [INDICA_CONSUMIDOR_FINAL] [bit],
										  [CODIGO_FISCAL_OPERACAO] [char](4),
										  [NF_ENTRADA_RELACIONADA] [char](15),
										  [SERIE_NF_RELACIONADA] [varchar](6) ,
										  [NOME_CLIFOR_RELACIONADA] [varchar](25),
										  [RECEBIMENTO_RELACIONADA] [datetime],
										  [QTDE] [numeric](9,3),
										  [CHAVE_NFE_SUBSTITUTO] [varchar](44),
										  [SEQ_ITEM_SUBSTITUTO] [char](4),
										  [COD_FECHAMENTO] [char](8),
										  [UNIDADE] [varchar](05),
										  [PRECO_UNITARIO] [numeric] (15,5),
										  [DESCRICAO_ITEM] [varchar] (80),
										  [NUMERO_MODELO_FISCAL] [varchar] (03),
										  [ITEM_IMPRESSAO] [char](4),
								  		  [SALDO_NF_SAIDA] [numeric](9,3) NULL,
										  [SEQ] [numeric] (3))
				
				-- tabela temporária das notas fiscais de saída selecionadas no período... 
				DECLARE @TMP_SAIDA_ORIGEM TABLE ([EMPRESA] [INT] ,
										  [COD_FILIAL] [char](06),
										  [NF_SAIDA] [char](15) ,
										  [SERIE_NF] [varchar](6) ,
										  [ITEM] [char](12) ,
										  [COR_ITEM] [char](10) ,
										  [TAMANHO] [varchar](8) ,
										  [QTDE_VENDIDA] [numeric](9,3) ,
										  [SEQ] [numeric] (3))

				-- Tabela temporária de CONTROLE_ENT_RESSARCIMENTO
				DECLARE @TMP_ENTRADA TABLE ([COD_FECHAMENTO] [char](08),
									  [EMPRESA] [int], 
									  [COD_FILIAL] [char](06), 
									  [FILIAL] [varchar](25), 
									  [NOME_CLIFOR] [varchar](25), 
									  [NF_ENTRADA] [char](15), 
									  [SERIE_NF] [varchar](6), 
									  [CHAVE_NFE] [varchar](44), 
									  [RECEBIMENTO] [datetime],
									  [VALOR_TOTAL] [numeric](14,2), 
									  [ITEM] [char](12), 
									  [COR_ITEM] [char](10), 
									  [TAMANHO] [varchar](8), 
									  [QTDE_ENTRADA] [numeric](9,3), 
									  [ALIQUOTA] [numeric](9,3), 
									  [BASE_ICMS_ST] [numeric](14,2),
									  [ICMS_EFETIVO] [numeric](14,2), 
									  [ICMS_PRESUMIDO] [numeric](14,2), 
									  [BASE_ICMS_PRESUMIDO] [numeric](14,2), 
									  [VALOR_ISENTO] [numeric](14,2),
									  [SEQ_ITEM_SUBSTITUTO] [char](4), 
									  [CHAVE_NFE_SUBSTITUTO] [varchar](44), 
									  [CODIGO_FISCAL_OPERACAO] [char](4),
									  [NATUREZA] [char](15), 
									  [SALDO_NF_ENTRADA] [numeric](9,3), 
									  [REFERENCIA] [varchar](50), 
									  [DESCRICAO_ITEM] [varchar](80), 
									  [NUMERO_MODELO_FISCAL] [varchar](03))

				-- Tabela temporária de CONTROLE_SALDO_RESSARCIMENTO
				DECLARE @TMP_SALDO_RESSARCIMENTO TABLE ([FILIAL] [varchar](25),
														[COD_FECHAMENTO] [char](8),
														[ITEM] [char](12),
														[ESTOQUE_INICIAL] [numeric](9,3),
														[ESTOQUE_FINAL] [numeric](9,3),
														[QTDE_MOV] [numeric](9,3),
														[ICMS_EFETIVO] [numeric](14,2),
														[ICMS_PRESUMIDO] [numeric](14,2),
														[COMPL_REST] [numeric](15,5),
														[TOTAL] [numeric](15,5))

				-- Selecionando as notas de saída do período selecionado...		
										  
				INSERT INTO @TMP_SAIDA (EMPRESA, COD_FILIAL, FILIAL, NOME_CLIFOR, NF_SAIDA, SERIE_NF, CHAVE_NFE, EMISSAO, VALOR_TOTAL, ITEM,
										COR_ITEM, TAMANHO, QTDE_VENDIDA, ALIQUOTA, BASE_ICMS_ST, ICMS_EFETIVO, ICMS_PRESUMIDO,
										BASE_ICMS_PRESUMIDO, VALOR_ISENTO, INDICA_CONSUMIDOR_FINAL, CODIGO_FISCAL_OPERACAO,
										NF_ENTRADA_RELACIONADA, SERIE_NF_RELACIONADA, NOME_CLIFOR_RELACIONADA, RECEBIMENTO_RELACIONADA,
										QTDE, CHAVE_NFE_SUBSTITUTO, SEQ_ITEM_SUBSTITUTO, COD_FECHAMENTO, UNIDADE, PRECO_UNITARIO, DESCRICAO_ITEM,
										NUMERO_MODELO_FISCAL, ITEM_IMPRESSAO, SALDO_NF_SAIDA, SEQ)
				SELECT C.EMPRESA, C.COD_FILIAL, A.FILIAL, A.NOME_CLIFOR, A.NF_SAIDA, ISNULL(A.SERIE_NF,''), A.CHAVE_NFE, A.EMISSAO, A.VALOR_TOTAL, J.PRODUTO,
					   SUBSTRING(LEFT(ISNULL(B.REFERENCIA_ITEM, ''),10),1,5) AS COR_ITEM, B.SUB_ITEM_TAMANHO AS TAMANHO, B.QTDE_ITEM, F.ALIQUOTA,
					   I.BASE_IMPOSTO AS BASE_ICMS_ST, D.VALOR_IMPOSTO, (G.BASE_IMPOSTO * (F.ALIQUOTA/100)) AS ICMS_PRESUMIDO, G.BASE_IMPOSTO AS BASE_ICMS_PRESUMIDO, 
					   CASE WHEN H.TRIBUT_ICMS IN ('40','41') THEN B.VALOR_ITEM ELSE 0.00 END AS VALOR_ISENTO, A.INDICA_CONSUMIDOR_FINAL,		  
					   B.CODIGO_FISCAL_OPERACAO, '' AS NF_ENTRADA_RELACIONADA, '' AS SERIE_NF_RELACIONADA, '' AS NOME_CLIFOR_RELACIONADA, 
					   NULL AS RECEBIMENTO_RELACIONADA, 0 AS QTDE, '' AS CHAVE_NFE_SUBSTITUTO, '' AS SEQ_SUBSTITUTO, @COD_FECHAMENTO,
					   B.UNIDADE, B.PRECO_UNITARIO, B.DESCRICAO_ITEM, '' AS NUMERO_MODELO_FISCAL, B.ITEM_IMPRESSAO, B.QTDE_ITEM, 0 AS SEQ
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
				AND D.ID_IMPOSTO = 1
				INNER JOIN CADASTRO_CLI_FOR E
				ON A.FILIAL = E.NOME_CLIFOR
				LEFT JOIN FATURAMENTO_IMPOSTO G
				ON B.FILIAL = G.FILIAL
				AND B.NF_SAIDA = G.NF_SAIDA
				AND B.SERIE_NF = G.SERIE_NF
				AND B.ITEM_IMPRESSAO = G.ITEM_IMPRESSAO
				AND B.SUB_ITEM_TAMANHO = G.SUB_ITEM_TAMANHO
				AND G.ID_IMPOSTO = 86
				LEFT JOIN CTB_EXCECAO_IMPOSTO H
				ON B.ID_EXCECAO_IMPOSTO = H.ID_EXCECAO_IMPOSTO
				AND H.TRIBUT_ICMS IN ('40','41')
				INNER JOIN FATURAMENTO_IMPOSTO I
				ON B.FILIAL = I.FILIAL
				AND B.NF_SAIDA = I.NF_SAIDA
				AND B.SERIE_NF = I.SERIE_NF
				AND B.ITEM_IMPRESSAO = I.ITEM_IMPRESSAO
				AND B.SUB_ITEM_TAMANHO = I.SUB_ITEM_TAMANHO
				AND I.ID_IMPOSTO IN ('12','13') 
				INNER JOIN RESSARCIMENTO_FILIAIS RF 
				ON RF.FILIAL = A.FILIAL
				AND RF.COD_FECHAMENTO = @COD_FECHAMENTO
				INNER JOIN PRODUTOS J ON (B.REFERENCIA=J.PRODUTO) 
				INNER JOIN PRODUTOS_UF_ICMS F 
				ON J.PRODUTO = F.PRODUTO
				AND F.UF = E.UF
				AND F.IS_ICMS_SUBSTITUTO = 1
				WHERE A.EMISSAO BETWEEN @DT_INI_RESS AND @DT_FIM_RESS 
				AND C.EMPRESA = @EMPRESA	

				INSERT INTO @TMP_SAIDA_ORIGEM (EMPRESA, COD_FILIAL, NF_SAIDA, SERIE_NF, ITEM, COR_ITEM, TAMANHO, QTDE_VENDIDA, SEQ)
				SELECT EMPRESA, COD_FILIAL, NF_SAIDA, SERIE_NF, ITEM, COR_ITEM, TAMANHO, QTDE_VENDIDA, SEQ
				FROM @TMP_SAIDA

				SET @IS_FINALIZOU_SAIDA = 0
				SET @IS_ACHOU_NF_ENTRADA = 0
				SET @ATUALIZA_SAIDA = 0

				SET @QTDE_ENTRADA = 0
				SET @QTDE_ENTRADA_SALDO = 0

				DECLARE CUR_SAIDA CURSOR LOCAL FAST_FORWARD FOR
				SELECT A.COD_FILIAL, A.NF_SAIDA, A.SERIE_NF, A.ITEM, A.TAMANHO, A.COR_ITEM, A.QTDE_VENDIDA, A.SEQ
				FROM @TMP_SAIDA_ORIGEM A

				OPEN CUR_SAIDA

				FETCH NEXT FROM CUR_SAIDA INTO @COD_FILIAL, @NF_SAIDA, @SERIE_NF, @ITEM, @TAMANHO, @COR_ITEM, @QTDE_VENDIDA, @SEQ

				SET @QTDE_SAIDA_SALDO = @QTDE_VENDIDA
				SET @SEQ_AUX = @SEQ

				WHILE @@FETCH_STATUS = 0
				BEGIN

					IF @IS_FINALIZOU_SAIDA = 1
						BEGIN
						FETCH NEXT FROM CUR_SAIDA INTO @COD_FILIAL, @NF_SAIDA, @SERIE_NF, @ITEM, @TAMANHO, @COR_ITEM, @QTDE_VENDIDA, @SEQ
						SET @QTDE_SAIDA_SALDO = @QTDE_VENDIDA
						SET @SEQ_AUX = @SEQ 
						SET @IS_FINALIZOU_SAIDA = 0
						END
			
					IF @QTDE_ENTRADA_SALDO = 0
						BEGIN
						SET @QTDE_ENTRADA = 0
						SET @NF_ENTRADA = ''
						SET @SERIE_NF_ENTRADA = ''
						SET @NOME_CLIFOR_ENTRADA = ''
						SET @RECEBIMENTO = ''
						SET @CHAVE_NFE_SUBSTITUTO = ''
						SET @SEQ_ITEM_SUBSTITUTO = ''
						
						DELETE FROM @TMP_ENTRADA 
						
						INSERT INTO @TMP_ENTRADA (COD_FECHAMENTO, EMPRESA, COD_FILIAL, FILIAL, NOME_CLIFOR, NF_ENTRADA, SERIE_NF, CHAVE_NFE, RECEBIMENTO,                          VALOR_TOTAL, ITEM, COR_ITEM, TAMANHO, QTDE_ENTRADA, ALIQUOTA, BASE_ICMS_ST,
												  ICMS_EFETIVO, ICMS_PRESUMIDO, BASE_ICMS_PRESUMIDO, VALOR_ISENTO,
												  SEQ_ITEM_SUBSTITUTO, CHAVE_NFE_SUBSTITUTO, CODIGO_FISCAL_OPERACAO,
												  NATUREZA, SALDO_NF_ENTRADA, REFERENCIA, DESCRICAO_ITEM, NUMERO_MODELO_FISCAL) 
						SELECT TOP 1 @COD_FECHAMENTO, C.EMPRESA, C.COD_FILIAL, A.FILIAL, A.NOME_CLIFOR, A.NF_ENTRADA, ISNULL(A.SERIE_NF_ENTRADA,''), A.CHAVE_NFE, A.RECEBIMENTO, A.VALOR_TOTAL, B.CODIGO_ITEM, SUBSTRING(LEFT(ISNULL(B.REFERENCIA_ITEM, ''),10),1,5) AS COR_ITEM, 
						B.SUB_ITEM_TAMANHO AS TAMANHO, B.QTDE_ITEM, D.ALIQUOTA, D.BASE_ICMS_SUBSTITUTO,
						F.VALOR_IMPOSTO AS ICMS_EFETIVO, D.ICMS_PRESUMIDO, D.BASE_ICMS_SUBSTITUTO AS BASE_ICMS_PRESUMIDO, 
						CASE WHEN G.TRIBUT_ICMS IN ('40','41') THEN B.VALOR_ITEM ELSE 0.00 END AS VALOR_ISENTO, 
						B.SEQ_ITEM_SUBSTITUTO, B.CHAVE_NFE_SUBSTITUTO, B.CODIGO_FISCAL_OPERACAO, A.NATUREZA, 
						B.QTDE_ITEM AS SALDO_NF_ENTRADA, B.REFERENCIA, B.DESCRICAO_ITEM, J.NUMERO_MODELO_FISCAL
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
						AND D.ID_IMPOSTO IN (12, 13)
						INNER JOIN ENTRADAS_IMPOSTO F
						ON B.NF_ENTRADA = F.NF_ENTRADA 
						AND B.SERIE_NF_ENTRADA = F.SERIE_NF_ENTRADA 
						AND B.NOME_CLIFOR = F.NOME_CLIFOR
						AND F.ID_IMPOSTO = 1
						LEFT JOIN CTB_EXCECAO_IMPOSTO G
						ON B.ID_EXCECAO_IMPOSTO = G.ID_EXCECAO_IMPOSTO
						AND G.TRIBUT_ICMS IN ('40','41')
						INNER JOIN CTB_ESPECIE_SERIE J
						ON A.ESPECIE_SERIE = J.ESPECIE_SERIE
						INNER JOIN NATUREZAS_ENTRADAS AS K ON A.NATUREZA = K.NATUREZA
						WHERE A.RECEBIMENTO <= @DT_FIM_RESS
						AND K.CTB_TIPO_OPERACAO IN ('200', '250') 			
						AND C.EMPRESA = @EMPRESA
						AND C.COD_FILIAL = @COD_FILIAL
						AND B.CODIGO_ITEM = @ITEM
						AND B.SUB_ITEM_TAMANHO = @TAMANHO		
						AND LEFT(ISNULL(B.REFERENCIA_ITEM, ''),10) = @COR_ITEM
						AND NOT EXISTS (SELECT 1
						FROM CONTROLE_ENT_RESSARCIMENTO X
						WHERE C.EMPRESA = X.EMPRESA
						AND C.COD_FILIAL = X.COD_FILIAL
						AND B.NF_ENTRADA = X.NF_ENTRADA 
						AND B.SERIE_NF_ENTRADA = X.SERIE_NF
						AND B.CODIGO_ITEM = X.ITEM
						AND LEFT(ISNULL(B.REFERENCIA_ITEM, ''),10)  = X.COR_ITEM
						AND B.SUB_ITEM_TAMANHO = X.TAMANHO) 
						ORDER BY A.RECEBIMENTO DESC

						SELECT TOP 1 @NF_ENTRADA = A.NF_ENTRADA, @SERIE_NF_ENTRADA = ISNULL(A.SERIE_NF,''), @QTDE_ENTRADA = ISNULL(A.QTDE_ENTRADA,0), 
						@NOME_CLIFOR_ENTRADA = A.NOME_CLIFOR, @RECEBIMENTO = A.RECEBIMENTO, @CHAVE_NFE_SUBSTITUTO = A.CHAVE_NFE_SUBSTITUTO,
						@SEQ_ITEM_SUBSTITUTO = A.SEQ_ITEM_SUBSTITUTO
						FROM @TMP_ENTRADA A
						
						IF @QTDE_ENTRADA > 0 
							BEGIN
								SET @QTDE_ENTRADA_SALDO = @QTDE_ENTRADA
								SET @IS_ACHOU_NF_ENTRADA = 1

								IF @SEQ < @SEQ_AUX
									BEGIN
										INSERT INTO @TMP_SAIDA (EMPRESA, COD_FILIAL, FILIAL, NOME_CLIFOR, NF_SAIDA, SERIE_NF, CHAVE_NFE, EMISSAO, VALOR_TOTAL, ITEM,
												COR_ITEM, TAMANHO, QTDE_VENDIDA, ALIQUOTA, BASE_ICMS_ST, ICMS_EFETIVO, ICMS_PRESUMIDO,
												BASE_ICMS_PRESUMIDO, VALOR_ISENTO, INDICA_CONSUMIDOR_FINAL, CODIGO_FISCAL_OPERACAO,
												NF_ENTRADA_RELACIONADA, SERIE_NF_RELACIONADA, NOME_CLIFOR_RELACIONADA, RECEBIMENTO_RELACIONADA,
												QTDE, CHAVE_NFE_SUBSTITUTO, SEQ_ITEM_SUBSTITUTO, COD_FECHAMENTO, UNIDADE, PRECO_UNITARIO, DESCRICAO_ITEM,
												NUMERO_MODELO_FISCAL, ITEM_IMPRESSAO, SALDO_NF_SAIDA, SEQ)
										SELECT 	EMPRESA, COD_FILIAL, FILIAL, NOME_CLIFOR, NF_SAIDA, SERIE_NF, CHAVE_NFE, EMISSAO, VALOR_TOTAL, ITEM,
												COR_ITEM, TAMANHO, QTDE_VENDIDA, ALIQUOTA, BASE_ICMS_ST, ICMS_EFETIVO, ICMS_PRESUMIDO,
												BASE_ICMS_PRESUMIDO, VALOR_ISENTO, INDICA_CONSUMIDOR_FINAL, CODIGO_FISCAL_OPERACAO,
												'' AS NF_ENTRADA_RELACIONADA, '' AS SERIE_NF_RELACIONADA, '' AS NOME_CLIFOR_RELACIONADA, '' AS RECEBIMENTO_RELACIONADA,
												0 AS QTDE, '' AS CHAVE_NFE_SUBSTITUTO, '' AS SEQ_ITEM_SUBSTITUTO, COD_FECHAMENTO, UNIDADE, PRECO_UNITARIO, DESCRICAO_ITEM,
												NUMERO_MODELO_FISCAL, ITEM_IMPRESSAO, @QTDE_SAIDA_SALDO, @SEQ_AUX
										FROM @TMP_SAIDA 
										WHERE COD_FILIAL = @COD_FILIAL
										AND NF_SAIDA = @NF_SAIDA
										AND SERIE_NF = @SERIE_NF
										AND ITEM = @ITEM
										AND TAMANHO = @TAMANHO
										AND COR_ITEM = @COR_ITEM
										AND SEQ = 0
										
										SET @SEQ = @SEQ_AUX
									END
							END
						ELSE
							BEGIN
								SET @QTDE_ENTRADA_SALDO = 0
								SET @IS_ACHOU_NF_ENTRADA = 0
								SET @IS_FINALIZOU_SAIDA = 1
							END
						END	

					SET @QTDE = 0		
					
					IF @QTDE_SAIDA_SALDO > 0 AND @QTDE_ENTRADA_SALDO > 0
						BEGIN	

						IF @QTDE_SAIDA_SALDO <= @QTDE_ENTRADA_SALDO
							BEGIN
								SET @QTDE = @QTDE_SAIDA_SALDO
								SET @QTDE_ENTRADA_SALDO = @QTDE_ENTRADA_SALDO - @QTDE_SAIDA_SALDO
								SET @QTDE_SAIDA_SALDO = 0
								SET @IS_FINALIZOU_SAIDA = 1
							END
						ELSE
							BEGIN
								SET @QTDE = @QTDE_ENTRADA_SALDO
								SET @QTDE_SAIDA_SALDO = @QTDE_SAIDA_SALDO - @QTDE_ENTRADA_SALDO
								SET @QTDE_ENTRADA_SALDO = 0
								SET @SEQ_AUX = @SEQ_AUX + 1
							END
							
						SET @ATUALIZA_SAIDA = 1	
						END
					ELSE
						BEGIN
							SET @IS_FINALIZOU_SAIDA = 1
							SET @ATUALIZA_SAIDA = 0	
						END

					-----------------------------------------------------------------------------------------------------------------------------------------  
					--Atualizando os campos na tabela CONTROLE_SAI_RESSARCIMENTO
					-----------------------------------------------------------------------------------------------------------------------------------------  
					IF @ATUALIZA_SAIDA = 1
						BEGIN
							UPDATE @TMP_SAIDA SET NF_ENTRADA_RELACIONADA = @NF_ENTRADA, SERIE_NF_RELACIONADA = @SERIE_NF_ENTRADA, 
							NOME_CLIFOR_RELACIONADA = @NOME_CLIFOR_ENTRADA, RECEBIMENTO_RELACIONADA = @RECEBIMENTO,
							QTDE = @QTDE, CHAVE_NFE_SUBSTITUTO = @CHAVE_NFE_SUBSTITUTO, SEQ_ITEM_SUBSTITUTO = @SEQ_ITEM_SUBSTITUTO, 
							SALDO_NF_SAIDA = @QTDE_SAIDA_SALDO
							WHERE COD_FILIAL = @COD_FILIAL AND NF_SAIDA = @NF_SAIDA AND SERIE_NF = @SERIE_NF AND ITEM = @ITEM AND TAMANHO = @TAMANHO AND COR_ITEM = @COR_ITEM AND SEQ = @SEQ
						END
					-- Identificando o Tipo Remetente
						

					-----------------------------------------------------------------------------------------------------------------------------------------  
					-- Inserindo as notas fiscais de entrada [tabela CONTROLE_ENT_RESSARCIMENTO]
					-----------------------------------------------------------------------------------------------------------------------------------------  
					-- Selecionando as notas de entrada do período selecionado...		
					-- tabela ENTRADAS, coluna NATUREZA, relacionar com a tabela NATUREZAS_ENTRADAS, buscar o tipo de operação na coluna CTB_TIPO_OPERACAO, 
					-- somente tipo operação igual a 200 (compra) e 250 (devolução).
					-----------------------------------------------------------------------------------------------------------------------------------------  
					IF @IS_ACHOU_NF_ENTRADA = 1 	
						BEGIN

							INSERT INTO CONTROLE_ENT_RESSARCIMENTO (COD_FECHAMENTO, EMPRESA, COD_FILIAL, FILIAL, NOME_CLIFOR, NF_ENTRADA, SERIE_NF, CHAVE_NFE, RECEBIMENTO,VALOR_TOTAL, ITEM, COR_ITEM, TAMANHO, QTDE_ENTRADA, ALIQUOTA, BASE_ICMS_ST,
											  ICMS_EFETIVO, ICMS_PRESUMIDO, BASE_ICMS_PRESUMIDO, VALOR_ISENTO,
											  SEQ_ITEM_SUBSTITUTO, CHAVE_NFE_SUBSTITUTO, CODIGO_FISCAL_OPERACAO,
											  NATUREZA, SALDO_NF_ENTRADA, REFERENCIA, DESCRICAO_ITEM, NUMERO_MODELO_FISCAL) 
							SELECT TOP 1 A.COD_FECHAMENTO, A.EMPRESA, A.COD_FILIAL, A.FILIAL, A.NOME_CLIFOR, A.NF_ENTRADA, A.SERIE_NF, A.CHAVE_NFE, A.RECEBIMENTO,A.VALOR_TOTAL, A.ITEM, A.COR_ITEM, A.TAMANHO, A.QTDE_ENTRADA, A.ALIQUOTA, A.BASE_ICMS_ST,
											  A.ICMS_EFETIVO, A.ICMS_PRESUMIDO, A.BASE_ICMS_PRESUMIDO, A.VALOR_ISENTO,
											  A.SEQ_ITEM_SUBSTITUTO, A.CHAVE_NFE_SUBSTITUTO, A.CODIGO_FISCAL_OPERACAO,
											  A.NATUREZA, A.SALDO_NF_ENTRADA, A.REFERENCIA, A.DESCRICAO_ITEM, A.NUMERO_MODELO_FISCAL
							FROM @TMP_ENTRADA A 


							SET @IS_ACHOU_NF_ENTRADA = 0
						END
					END
				--Inserindo na tabela CONTROLE_SAI_RESSARCIMENTO
				INSERT INTO CONTROLE_SAI_RESSARCIMENTO (EMPRESA, COD_FILIAL, FILIAL, NOME_CLIFOR, NF_SAIDA, SERIE_NF, CHAVE_NFE, EMISSAO,
										VALOR_TOTAL, ITEM, COR_ITEM, TAMANHO, QTDE_VENDIDA, ALIQUOTA, BASE_ICMS_ST, ICMS_EFETIVO, ICMS_PRESUMIDO,
										BASE_ICMS_PRESUMIDO, VALOR_ISENTO, INDICA_CONSUMIDOR_FINAL, CODIGO_FISCAL_OPERACAO,
										NF_ENTRADA_RELACIONADA, SERIE_NF_RELACIONADA, NOME_CLIFOR_RELACIONADA, RECEBIMENTO_RELACIONADA,
										QTDE, CHAVE_NFE_SUBSTITUTO, SEQ_ITEM_SUBSTITUTO, COD_FECHAMENTO, UNIDADE, PRECO_UNITARIO, DESCRICAO_ITEM, NUMERO_MODELO_FISCAL, ITEM_IMPRESSAO, SALDO_NF_SAIDA, SEQ)
				SELECT EMPRESA, COD_FILIAL, FILIAL, NOME_CLIFOR, NF_SAIDA, SERIE_NF, CHAVE_NFE, EMISSAO, VALOR_TOTAL, ITEM,
										COR_ITEM, TAMANHO, QTDE_VENDIDA, ALIQUOTA, BASE_ICMS_ST, ICMS_EFETIVO, ICMS_PRESUMIDO,
										BASE_ICMS_PRESUMIDO, VALOR_ISENTO, INDICA_CONSUMIDOR_FINAL, CODIGO_FISCAL_OPERACAO,
										ISNULL(NF_ENTRADA_RELACIONADA,''), ISNULL(SERIE_NF_RELACIONADA,''), ISNULL(NOME_CLIFOR_RELACIONADA,''), ISNULL(RECEBIMENTO_RELACIONADA, '1900-01-01'),
										ISNULL(QTDE,0), CHAVE_NFE_SUBSTITUTO, SEQ_ITEM_SUBSTITUTO, @COD_FECHAMENTO, UNIDADE, PRECO_UNITARIO, DESCRICAO_ITEM,NUMERO_MODELO_FISCAL, ITEM_IMPRESSAO, SALDO_NF_SAIDA, SEQ
				FROM @TMP_SAIDA
				
				-----------------------------------------------------------------------------------------------------------------------------------------------
				-- atualizando a tabela CONTROLE_SALDO_RESSARCIMENTO
				-----------------------------------------------------------------------------------------------------------------------------------------------

				INSERT INTO CONTROLE_SALDO_RESSARCIMENTO (COD_FECHAMENTO, FILIAL, ITEM, ESTOQUE_INICIAL, ESTOQUE_FINAL, QTDE_MOV, 
				                                          ICMS_EFETIVO, ICMS_PRESUMIDO, COMPL_REST, TOTAL) 
				SELECT A.COD_FECHAMENTO, A.FILIAL, A.ITEM, 0 AS ESTOQUE_INICIAL, SUM(ISNULL(A.QTDE,0)) AS ESTOQUE_FINAL, SUM(ISNULL(A.QTDE,0)) AS QTDE_MOV, SUM(ISNULL(A.ICMS_EFETIVO,0)) AS ICMS_EFETIVO, SUM(ISNULL(A.ICMS_PRESUMIDO,0)) AS ICMS_PRESUMIDO, SUM(ISNULL(A.ICMS_EFETIVO,0) - ISNULL(A.ICMS_PRESUMIDO,0)) AS COMPL_REST, SUM(ISNULL(A.ICMS_EFETIVO,0) - ISNULL(A.ICMS_PRESUMIDO,0)) AS TOTAL 
				FROM CONTROLE_SAI_RESSARCIMENTO A
				WHERE A.COD_FECHAMENTO = @COD_FECHAMENTO
				GROUP BY A.COD_FECHAMENTO, A.FILIAL, A.ITEM
				
				-----------------------------------------------------------------------------------------------------------------------------------------------
				UPDATE DADOS_FECHAMENTO_RESSARCIMENTO  
				SET DATA_GERACAO = CONVERT(DATETIME, CONVERT(CHAR(10), GETDATE(), 112))  
				WHERE COD_FECHAMENTO = @COD_FECHAMENTO  
				-----------------------------------------------------------------------------------------------------------------------------------------------

				-----------------------------------------------------------------------------------------------------------------------------------------------
				-- Atualizando o campo TIPO_REMENTENTE da tabela CONTROLE_ENT_RESSARIMENTO
				-----------------------------------------------------------------------------------------------------------------------------------------------
				--#ADALBERTO#-VERIFICAR... 
				--UPDATE CONTROLE_ENT_RESSARCIMENTO SET TIPO_REMETENTE = FX_RETORNA_TIPO_REMETENTE(CONTROLE_ENT_RESSARCIMENTO.NF_ENTRADA, --CONTROLE_ENT_RESSARCIMENTO.SERIE_NF_ENTRADA, CONTROLE_ENT_RESSARCIMENTO.NOME_CLIFOR, CONTROLE_ENT_RESSARCIMENTO.ITEM_IMPRESSAO) WHERE --CONTROLE_ENT_RESSARCIMENTO.COD_FECHAMENTO = @COD_FECHAMENTO
				-----------------------------------------------------------------------------------------------------------------------------------------------

				
				SET NOCOUNT OFF
				-----------------------------------------------------------------------------------------------------------------------------------------------
				-- VERIFICA SE EXISTE UMA PROCEDURE CUSTOMIZADA DO CLIENTE PARA FECHAMENTO DE RESSARCIMENTO				-----------------------------------------------------------------------------------------------------------------------------------------------
				IF EXISTS( SELECT * FROM SYSOBJECTS WHERE NAME = 'LX_FECHAMENTO_RESSARCIMENTO_OE_FINAL' )
					EXECUTE LX_FECHAMENTO_RESSARCIMENTO_OE_FINAL @COD_FECHAMENTO, @EMPRESA
				-----------------------------------------------------------------------------------------------------------------------------------------------
			END
		END
	END
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



