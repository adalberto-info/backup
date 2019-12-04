CREATE PROCEDURE [dbo].[LX_FECHAMENTO_RESSARCIMENTO] @COD_FECHAMENTO AS CHAR(8), @EMPRESA AS INT  
AS  

	BEGIN TRY 
	 
	-------------------------------------------------------------------------------------------------------------------------------------------------  
	-- Procedure para geração das tabelas CONTROLE_ENT_RESSARCIMENTO e CONTROLE_SAI_RESSARCIMENTO                                                  --  
	-------------------------------------------------------------------------------------------------------------------------------------------------
	-- 04/12/2019 - Adalberto (WAFX) - #0# - MODASP-2413   - Criação da stored procedure LX_FECHAMENTO_RESSARCIMENTO.                              --
	-------------------------------------------------------------------------------------------------------------------------------------------------  
	 
	SET NOCOUNT ON  
	 
	DECLARE @UTILIZA_SALDO_ANTERIOR AS BIT, @COD_FECHAMENTO_ANTERIOR AS CHAR(8), @PERIODO_ANTERIOR AS CHAR(06), @PERIODO AS CHAR(06), @DATA_FECHAMENTO AS DATETIME, @ERRMSG  VARCHAR(255)

	SELECT @UTILIZA_SALDO_ANTERIOR = A.UTILIZA_SALDO_ANTERIOR,  
		   @COD_FECHAMENTO_ANTERIOR = A.COD_FECHAMENTO_ANTERIOR, 
		   @PERIODO = A.PERIODO
	FROM DADOS_FECHAMENTO_RESSARCIMENTO AS A (NOLOCK)  
	WHERE A.COD_FECHAMENTO = @COD_FECHAMENTO  
	
	SELECT 	@PERIODO_ANTERIOR = DADOS_FECHAMENTO_RESSARCIMENTO.PERIODO FROM DADOS_FECHAMENTO_RESSARCIMENTO WHERE COD_FECHAMENTO=@COD_FECHAMENTO_ANTERIOR 


	------------------------------------------------------------------------------------------------------------------------------------------------
	-- VERIFICA SE EXISTE UMA PROCEDURE DE USUÁRIO PARA FECHAMENTO DO RESSARCIMENTO
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
	 
	UPDATE DADOS_FECHAMENTO_RESSARCIMENTO  
	SET DATA_GERACAO = CONVERT(DATETIME, CONVERT(CHAR(10), GETDATE(), 112))  
	WHERE COD_FECHAMENTO = @COD_FECHAMENTO  

	-------------------------------------------------------------------------------------------------------------------------------------------------	
	  
	SET NOCOUNT OFF

	------------------------------------------------------------------------------------------------------------------------------------------------
	-- VERIFICA SE EXISTE UMA PROCEDURE DE USUÁRIO PARA FECHAMENTO DE RESSARCIMENTO
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

GO


