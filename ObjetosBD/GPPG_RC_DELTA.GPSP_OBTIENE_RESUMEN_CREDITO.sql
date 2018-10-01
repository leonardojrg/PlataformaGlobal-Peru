/*
-Autor/Empresa: Leonardo Ramirez/Eon
-Objetivo: Devuelve 3 cursores con la información del resumen de crédito a nivel persona, producto y el detalle de los productos
-Historial de modificaciones:
	-->Autor/Empresa: Leonardo Julián Ramirez/Eon
	-->Version 1.0
	-->Modificación: Esta versión se implemento en el segundo PI donde se liberó a producción con el producto minimo viable.
*/

PROCEDURE  GPSP_OBTIENE_RESUMEN_CREDITO(
        p_NUM_PERSONA IN NUMBER
        ,SP_RESUMEN_PERSONA OUT CURSOR_TYPE
        ,SP_RESUMEN_PRODUCTO OUT  CURSOR_TYPE
        ,SP_RESUMEN_DETALLE OUT CURSOR_TYPE
        ,v_Mensaje_Error OUT VARCHAR2
        )
  AS
    --v_XML_ResumenCred XMLTYPE;
    err_num         NUMBER;
    v_InicioProceso VARCHAR2(100);
    v_FinProceso    VARCHAR2(100);
    v_numRegistro   NUMBER;

    v_FEC_CARGA_AFP DATE;
    v_FEC_CONSULTA DATE;
    v_ENTIDAD_SUN    NUMBER;
    v_FUENTE_DEU   NUMBER;


  BEGIN
    SELECT TO_CHAR(SYSTIMESTAMP,'hh24:mi:ss.FF') INTO v_InicioProceso FROM DUAL;

    SELECT TO_NUMBER(TO_CHAR(SYSDATE, 'yyyymmddhh24miss')) INTO v_numRegistro FROM DUAL;

      SELECT TRUNC(SYSDATE)
      INTO  v_FEC_CONSULTA
      FROM DUAL;

      SELECT  LAST_DAY(NVL(MAX(FEC_PERIODO),TRUNC(SYSDATE))) FECHA_AFP
      INTO v_FEC_CARGA_AFP     
      FROM GPT_CARGA_LOTES
      WHERE CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('AFP') FROM DUAL)
          AND  FEC_CANCELACION IS NULL
          AND  FEC_PERIODO >=  (SELECT LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE),-24)) + 1 FROM DUAL);


     SELECT (SELECT GPPG_RC.get_entidad('SUNAT') FROM DUAL)
              ,(SELECT GPPG_RC.get_fuente('DEUDORES')FROM DUAL)
     INTO v_ENTIDAD_SUN
            ,v_FUENTE_DEU
     FROM DUAL;


  /*****************INICIO OTROS CONCEPTOS DE LA RCC***********************/
INSERT INTO  TMP_RESUMEN_CREDITO
        ( 
        CVE_TIPO_TARJETA
        ,CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE
        ,TOT_DEUDA_DIRECTA
        ,IDCALIFICACION
        ,CALIFICACION
        ,MAX_MOROSIDAD_12
        ,MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,JUDICIAL
        ,INTERESES
        ,PCT_MOROSA
        ,PCT_MONEDA_EXTRANJERA
        ,DEUDA_INDIRECTA
        ,LINEA_CREDITO
        ,DEUDA_CORRIENTE
        ,DEUDA_MOROSA
        ,NUM_PERSONA
        ,ES_INTERES
        ,NUMERO_REGISTRO
        )

WITH FECHAS_ENTIDADES AS (
  SELECT    /*+ ALL_ROWS */

            LAST_DAY(NVL(MAX(DECODE(CVE_ENTIDAD,GPPG_RC.get_entidad('SBS'),DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('RCC'),FEC_PERIODO,NULL),NULL)),TRUNC(SYSDATE))) FEC_CARGA_RCC
           ,MAX(DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('DEUDORES'),FEC_PERIODO,NULL)) FEC_PERIODO_GLOBAL_ENTIDAD 
            ,LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE),-1)) FEC_TIPO_CAMBIO /* PARA EL TIPO DE CAMBIO */
            ,TRUNC(SYSDATE) FEC_CONSULTA
           ,LAST_DAY(TRUNC(SYSDATE)) FEC_LASTDAYCONSULTA /* FECHA DE CONSULTA A ULTIMO DIA DE MES */
         FROM GPT_CARGA_LOTES
         WHERE
         FEC_CANCELACION IS NULL
         AND  (
                  (CVE_ENTIDAD = (SELECT GPPG_RC.get_entidad('SBS') FROM DUAL)
                    AND  CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('RCC') FROM DUAL)
                  )               
                )
         AND  FEC_PERIODO >=  (SELECT LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE),-24)) + 1 FROM DUAL)       


), LISTADO_CUENTAS_RCC AS
(
SELECT 
        C.NUM_SALDO ,
        C.CVE_CUENTA ,
        C.CVE_EMPRESA ,
        CC.CVE_RUBRO ,
        CC.CVE_TIPO ,
        CC.CVE_MODALIDAD ,
        CC.CVE_SUBMODALIDAD ,
        CC.CVE_SITUACION ,
        VIS.FEC_PERIODO,
        VIS.CVE_CLASIFICACION CALIFICACION,
        VIS.CAN_CON_DIAS,
        VIS.IMP_MTO_SALDO,
        C.CVE_MONEDA
FROM GPT_CREDITO C
    INNER JOIN GPC_CUENTAS_CONTABLES CC 
            ON CC.CVE_CUENTA = C.CVE_CUENTA
    INNER JOIN TABLE(GPPG_RC_DELTA.GET_DATOS_VISIBLES_RCC(p_NUM_PERSONA)) VIS --TABLA CON REGLAS DE VISIBILIDAD APLICADAS
            ON VIS.NUM_SALDO = C.NUM_SALDO
            AND VIS.NUM_PERSONA = C.NUM_PERSONA
    CROSS JOIN   FECHAS_ENTIDADES FE

), OTROS_CONCEPTOS_RCC AS 
(
    /* LINEA DE CREDITO, CASTIGOS*/
    SELECT 
        CVE_TIPO_CREDITO
        ,CVE_PRODUCTO
        ,FEC_PERIODO
        ,COUNT(CVE_EMPRESA) N_REGISTROS
        ,SUM(IMP_MTO_SALDO) IMP_MTO_SALDO
        ,MAX(CAN_CON_DIAS)  CAN_CON_DIAS
        ,MAX(DECODE(MAX_FEC_PERIODO,FEC_CARGA_RCC,6,5)) CALIFICACION/*SI ES REPORTADO EN CARGA ACTUAL SIGUE SIENDO MOROSO, EN CASO CONTRARIO ES CERRADO*/
        ,MAX(MOROSIDAD_12MESES) MAX_MOROSIDAD_12
        ,MAX(MONTHS_BETWEEN(FEC_CARGA_RCC,ADD_MONTHS(MIN_FEC_PERIODO,-1) )) ANTIGUEDAD     
        FROM 
        (
            SELECT 
                C_PROD.CVE_TIPO_CREDITO
                ,C_PROD.CVE_PRODUCTO
                ,RCC.CVE_EMPRESA 
                ,RCC.IMP_MTO_SALDO
                ,RCC.CAN_CON_DIAS
                ,MAX(RCC.FEC_PERIODO) OVER (PARTITION BY C_PROD.CVE_TIPO_CREDITO,C_PROD.CVE_PRODUCTO) MAX_FEC_PERIODO
                ,MIN(RCC.FEC_PERIODO) OVER (PARTITION BY C_PROD.CVE_TIPO_CREDITO,C_PROD.CVE_PRODUCTO) MIN_FEC_PERIODO
                ,RCC.FEC_PERIODO 
                ,FE.FEC_CARGA_RCC
                ,(CASE WHEN RCC.FEC_PERIODO BETWEEN ADD_MONTHS(FE.FEC_CARGA_RCC,-24)  AND FE.FEC_CARGA_RCC
                        THEN RCC.CAN_CON_DIAS
                    ELSE 0 END) MOROSIDAD_12MESES
            FROM LISTADO_CUENTAS_RCC RCC
            JOIN GPC_PRODUCTO_AGRUPAMIENTO C_PROD /*+ FIRST_ROWS */
                ON RCC.CVE_RUBRO=C_PROD.CVE_RUBRO
                    AND RCC.CVE_TIPO=DECODE(C_PROD.CVE_TIPO,NULL,RCC.CVE_TIPO,C_PROD.CVE_TIPO)
                    AND RCC.CVE_SITUACION=DECODE(C_PROD.CVE_SITUACION,NULL,RCC.CVE_SITUACION,C_PROD.CVE_SITUACION)
                    AND RCC.CVE_MODALIDAD=DECODE(C_PROD.CVE_MODALIDAD,NULL,RCC.CVE_MODALIDAD,C_PROD.CVE_MODALIDAD)
                    AND RCC.CVE_SUBMODALIDAD=DECODE(C_PROD.CVE_SUBMODALIDAD,NULL,RCC.CVE_SUBMODALIDAD,C_PROD.CVE_SUBMODALIDAD)
           CROSS JOIN FECHAS_ENTIDADES FE
             WHERE C_PROD.CVE_TIPO_AGRUPAMIENTO IN ('02','13','12','11')  /*02 LINEA DE CREDITO*/
        )


     WHERE FEC_PERIODO=MAX_FEC_PERIODO
     GROUP BY 
        CVE_TIPO_CREDITO
        ,CVE_PRODUCTO
        ,FEC_PERIODO


)
,CONSOLIDADO_CASTIGOS AS
(

  SELECT        3 OrdenFuente /*1.- Fuente RCC, para ordenamiento*/
                ,CC.CVE_TIPO_CREDITO
                ,CC.CVE_PRODUCTO   
                ,FEC_PERIODO FECHA_REPORTE_SBS
                ,CALIFICACION
                ,ER.REF_DESCRIPCION_CORTA DES_CALIFICACION
                ,MAX_MOROSIDAD_12
                ,C_PROD.DES_TIPO_CREDITO
                ,C_PROD.DES_PRODUCTO
                ,CAN_CON_DIAS  MAX_MOROSIDAD_ACTUAL
                ,ANTIGUEDAD
                ,N_REGISTROS NUM_ENTIDADES
                ,0 ENT_CON_ATRASO
                ,0 VIGENTE
                ,0 REESTRUCTURADO
                ,0 REFINANCIADO
                ,IMP_MTO_SALDO VENCIDO
                ,0 JUDICIAL
                ,0 INTERESES
                ,0 SALDO_MN
                ,IMP_MTO_SALDO
                ,0 OrdenProducto /*OrdenamientoProducto*/
                ,0 LINEA_CREDITO 
        FROM OTROS_CONCEPTOS_RCC CC
     INNER JOIN (SELECT CVE_TIPO_CREDITO, CVE_PRODUCTO,DES_TIPO_CREDITO,DES_PRODUCTO 
                            FROM GPC_PRODUCTO_AGRUPAMIENTO 
                                GROUP BY CVE_TIPO_CREDITO, CVE_PRODUCTO,DES_TIPO_CREDITO,DES_PRODUCTO) C_PROD /*OBTENER ETIQUETAS DE PRODUCTO Y TIPO_PRODUCTO*/
                ON C_PROD.CVE_TIPO_CREDITO=CC.CVE_TIPO_CREDITO
                AND C_PROD.CVE_PRODUCTO=CC.CVE_PRODUCTO
     INNER JOIN GPC_ETIQUETAS_REPORTE ER
               ON ER.CVE_ETIQUETA IN ('CL005','CL006') 
               AND ER.CVE_ETIQUETA=DECODE(CALIFICACION,6,'CL006','CL005')
    WHERE CC.CVE_TIPO_CREDITO IN ('MOR','OTR')
        OR (CC.CVE_TIPO_CREDITO IN ('CC') AND CC.CVE_PRODUCTO IN ('LC'))
)
SELECT 
        3 TIPO_TARJETA /*-3. Chica*/
        ,CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE_SBS
        ,VENCIDO TOT_DEUDA_DIRECTA
        ,CALIFICACION IDCALIFICACION
        ,DES_CALIFICACION CALIFICACION
        ,MAX_MOROSIDAD_12
        ,MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,JUDICIAL
        ,INTERESES
        ,100.00 PCT_MOROSA
        ,DECODE(SALDO_MN,0,0,((SALDO_MN/VENCIDO)*100))  PCT_MONEDA_EXTRANJERA
        ,0 DEUDA_INDIRECTA 
        ,LINEA_CREDITO LINEA_CREDITO
        ,0 DEUDA_CORRIENTE
        ,VENCIDO DEUDA_MOROSA
    ,p_NUM_PERSONA
        ,0 ES_INTERES
        ,v_numRegistro
    FROM CONSOLIDADO_CASTIGOS;

    /*****************FIN OTROS CONCEPTOS DE LA RCC***********************/
COMMIT;
    /*****************INICIO CUENTAS DE LA RCC***************************/

INSERT INTO  TMP_RESUMEN_CREDITO
        ( 
        CVE_TIPO_TARJETA
        ,CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE
        ,TOT_DEUDA_DIRECTA
        ,IDCALIFICACION
        ,CALIFICACION
        ,MAX_MOROSIDAD_12
        ,MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,JUDICIAL
        ,INTERESES
        ,PCT_MOROSA
        ,PCT_MONEDA_EXTRANJERA
        ,DEUDA_INDIRECTA
        ,LINEA_CREDITO
        ,DEUDA_CORRIENTE
        ,DEUDA_MOROSA
    ,NUM_PERSONA
    ,ES_INTERES
        ,NUMERO_REGISTRO)

WITH FECHAS_ENTIDADES AS (
  SELECT    /*+ ALL_ROWS */

            LAST_DAY(NVL(MAX(DECODE(CVE_ENTIDAD,GPPG_RC.get_entidad('SBS'),DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('RCC'),FEC_PERIODO,NULL),NULL)),TRUNC(SYSDATE))) FEC_CARGA_RCC
           ,MAX(DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('DEUDORES'),FEC_PERIODO,NULL)) FEC_PERIODO_GLOBAL_ENTIDAD 
            ,LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE),-1)) FEC_TIPO_CAMBIO /* PARA EL TIPO DE CAMBIO */
           ,TRUNC(SYSDATE) FEC_CONSULTA
           ,LAST_DAY(TRUNC(SYSDATE)) FEC_LASTDAYCONSULTA /* FECHA DE CONSULTA A ULTIMO DIA DE MES */
         FROM GPT_CARGA_LOTES
         WHERE
         FEC_CANCELACION IS NULL
         AND  (
                  (CVE_ENTIDAD = (SELECT GPPG_RC.get_entidad('SBS') FROM DUAL)
                    AND  CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('RCC') FROM DUAL)
                  )    
                )
         AND  FEC_PERIODO >=  (SELECT LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE),-24)) + 1 FROM DUAL)       


), LISTADO_CUENTAS_RCC AS
(
SELECT 
        C.NUM_SALDO ,
        C.CVE_CUENTA ,
        C.CVE_EMPRESA ,
        CC.CVE_RUBRO ,
        CC.CVE_TIPO ,
        CC.CVE_MODALIDAD ,
        CC.CVE_SUBMODALIDAD ,
        CC.CVE_SITUACION ,
        VIS.FEC_PERIODO,
        VIS.CVE_CLASIFICACION CALIFICACION,
        VIS.CAN_CON_DIAS,
        VIS.IMP_MTO_SALDO,
        C.CVE_MONEDA
FROM GPT_CREDITO C
    INNER JOIN GPC_CUENTAS_CONTABLES CC 
            ON CC.CVE_CUENTA   =C.CVE_CUENTA
    INNER JOIN TABLE(GPPG_RC_DELTA.GET_DATOS_VISIBLES_RCC(p_NUM_PERSONA)) VIS --TABLA CON REGLAS DE VISIBILIDAD APLICADAS
            ON VIS.NUM_SALDO = C.NUM_SALDO
            AND VIS.NUM_PERSONA = C.NUM_PERSONA
    CROSS JOIN   FECHAS_ENTIDADES FE
)
, PRE_CONSOLIDADO_CUENTAS_RCC AS
(
    /*AGRUPAMIENTOS DE LA RCC PARA RUBRO 14*/
       SELECT DISTINCT 
        C_PROD.CVE_TIPO_CREDITO
        ,(CASE 
            WHEN C_PROD.CVE_TIPO_CREDITO ='CC'  /*CRvâDITO DE CONSUMO*/
                THEN (CASE  
                    WHEN RCC.CVE_MODALIDAD='02' THEN 'TJ'  /*TARJETA DE CREDITO*/
                    WHEN RCC.CVE_MODALIDAD='13' THEN 'PIG'  /*PIGNORATICIOS*/
                    WHEN RCC.CVE_MODALIDAD='06' THEN  DECODE(RCC.CVE_SUBMODALIDAD, '02','PA', 'OP') /*PRvâSTAMO PARA AUTOS Y OTROS PRESTAMOS DE CONSUMO */
                    WHEN RCC.CVE_MODALIDAD NOT IN ('01','06','13') THEN 'OCC' /*OTROS CRvâDITOS DE CONSUMO*/ 
                    ELSE NULL
                    END)
            WHEN C_PROD.CVE_TIPO_CREDITO ='HIP' /*HIPOTECARIO*/
                THEN (CASE  
                    WHEN RCC.CVE_MODALIDAD='06' THEN 'PR'  /*PRESTAMOS*/
                    WHEN RCC.CVE_MODALIDAD='23' THEN 'FMV'  /*FONDO MI VIVIENDA*/
                    ELSE 'OCH' /*OTROS CRvâDITOS HIPOTECARIOS*/
                    END)
            WHEN C_PROD.CVE_TIPO_CREDITO ='MIC' /*MICROEMPRESA*/
                THEN (CASE  
                    WHEN  RCC.CVE_MODALIDAD='02' THEN 'TJ'  /*TARJETA DE CRvâDITO*/
                    WHEN  RCC.CVE_MODALIDAD='04' THEN 'SOB' /*SOBREGIROS EN CUENTA*/
                    WHEN  RCC.CVE_MODALIDAD='06' THEN 'PR' /*PRESTAMOS*/
                    WHEN  RCC.CVE_MODALIDAD='11' THEN 'AF' /*ARRENDAMIENTO FINANCIERO*/ 
                    ELSE 'OCM'/*OTROS CRvâDITOS A MICROEMPRESAS*/ 
                    END)
            WHEN C_PROD.CVE_TIPO_CREDITO ='PQE' /*PEQUEvëA EMPRESA*/
                THEN (
                    CASE  
                WHEN   RCC.CVE_MODALIDAD='02' THEN 'TJ'  /*TARJETA DE CRvâDITO*/
                WHEN   RCC.CVE_MODALIDAD='04' THEN 'SOB' /*SOBREGIROS EN CUENTA*/
                WHEN   RCC.CVE_MODALIDAD='06' THEN 'PR' /*PRESTAMOS*/
                WHEN   RCC.CVE_MODALIDAD='11' THEN 'AF' /*ARRENDAMIENTO FINANCIERO*/ 
                ELSE 'OCP'/*OTROS CRvâDITOS A PEQUEvëAS EMPRESAS*/ 
                END
                    )
            WHEN C_PROD.CVE_TIPO_CREDITO ='MED' /*MEDIANA EMPRESA*/
                THEN (
                CASE  
                WHEN   RCC.CVE_MODALIDAD='02' THEN 'TJ'  /*TARJETA DE CRvâDITO*/
                WHEN   RCC.CVE_MODALIDAD='04' THEN 'SOB' /*SOBREGIROS EN CUENTA*/
                WHEN   RCC.CVE_MODALIDAD='05' THEN 'DES' /*DESCUENTOS*/
                WHEN   RCC.CVE_MODALIDAD='06' THEN 'PR' /*PRESTAMOS*/
                WHEN   RCC.CVE_MODALIDAD='11' THEN 'AF' /*ARRENDAMIENTO FINANCIERO*/ 
                ELSE 'OCM'/*OTROS CRvâDITOS A MEDIANAS EMPRESAS*/ 
                END
                )
            WHEN C_PROD.CVE_TIPO_CREDITO ='GDE' /*GRANDE EMPRESA*/
                THEN (
                CASE  
                WHEN   RCC.CVE_MODALIDAD='02' THEN 'TJ'  /*TARJETA DE CRvâDITO*/
                WHEN   RCC.CVE_MODALIDAD='05' THEN 'DES' /*DESCUENTOS*/
                WHEN   RCC.CVE_MODALIDAD='06' THEN 'PR' /*PRESTAMOS*/
                WHEN   RCC.CVE_MODALIDAD='11' THEN 'AF' /*ARRENDAMIENTO FINANCIERO*/ 
                ELSE 'OCG'/*OTROS CRvâDITOS A GRANDES*/ 
                END
                )
            --Inicio PR-280
                WHEN C_PROD.CVE_TIPO_CREDITO ='COR' /*Corporativo*/
                    THEN CVE_PRODUCTO
                WHEN C_PROD.CVE_TIPO_CREDITO ='BMD' /*Bancos multilaterales de desarrollo*/
                    THEN CVE_PRODUCTO
                WHEN C_PROD.CVE_TIPO_CREDITO ='SBR' /*Soberanos*/
                    THEN CVE_PRODUCTO
                WHEN C_PROD.CVE_TIPO_CREDITO ='ESP' /*Entidades del sector pv¿blico*/
                    THEN CVE_PRODUCTO
                WHEN C_PROD.CVE_TIPO_CREDITO ='IV' /*Intermediarios de valores*/
                    THEN CVE_PRODUCTO
                WHEN C_PROD.CVE_TIPO_CREDITO ='ESF' /*Empresas del sistema financiero*/
                    THEN CVE_PRODUCTO
            --FIN PR-280
            END ) CVE_PRODUCTO
        ,RCC.CVE_RUBRO
        ,RCC.CVE_TIPO
        ,RCC.CVE_MODALIDAD
        ,RCC.CVE_SUBMODALIDAD
        ,RCC.CVE_SITUACION
        ,RCC.CVE_EMPRESA 
        ,RCC.CAN_CON_DIAS 
        ,RCC.FEC_PERIODO
        ,RCC.CALIFICACION
        ,RCC.IMP_MTO_SALDO
    ,DECODE(RCC.CVE_SITUACION,8,1,9,1,0) ES_INTERES
    FROM LISTADO_CUENTAS_RCC RCC
    JOIN GPC_PRODUCTO_AGRUPAMIENTO C_PROD /*+ ALL_ROWS */ 
        ON RCC.CVE_RUBRO=C_PROD.CVE_RUBRO
        AND RCC.CVE_TIPO=C_PROD.CVE_TIPO
    WHERE C_PROD.CVE_TIPO_AGRUPAMIENTO IN('01','03','04','05','06','07','08')

) 
    , CONSOLIDADO_CUENTAS_RCC AS(

    SELECT 
        1 OrdenFuente /*1.- Fuente RCC, para ordenamiento*/
        ,CVE_TIPO_CREDITO
        ,CVE_PRODUCTO
        ,FECHA_REPORTE_SBS
        ,CALIFICACION
        ,(SELECT DES_CLASIFICACION 
            FROM GPC_CLASIFICACION CLAS /*+ INDEX(GPCNS_PK_CLAS_CVECLASIF) */ 
            WHERE CLAS.CVE_CLASIFICACION=CALIFICACION) DES_CALIFICACION
        ,MAX_MOROSIDAD_12
        ,DES_TIPO_CREDITO
        ,DES_PRODUCTO
        ,DECODE(CALIFICACION,9,0,MAX_MOROSIDAD_ACTUAL) MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE 
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,JUDICIAL
        ,INTERESES
        ,SALDO_MN
        ,IMP_MTO_SALDO
        ,ES_INTERES
        ,OrdenProducto
        ,LINEA_CREDITO
        FROM(
    SELECT 
           CVE_TIPO_CREDITO
          ,CVE_PRODUCTO   
          ,MAX(FECHA_REPORTE_SBS) FECHA_REPORTE_SBS
          ,MAX(CALIFICACION) CALIFICACION /*SI NO APARECE EN LA /LTIMA CARGA, LA CUENTA ESTA CERRADA*/
          ,MAX(MAX_MOROSIDAD_12) MAX_MOROSIDAD_12
          ,MAX(DES_TIPO_CREDITO) DES_TIPO_CREDITO
          ,MAX(DES_PRODUCTO) DES_PRODUCTO
          ,MAX(MAX_MOROSIDAD_ACTUAL)  MAX_MOROSIDAD_ACTUAL
          ,MAX(ANTIGUEDAD) ANTIGUEDAD
          /*INICIA PR-283*/
          ,SUM(NUM_ENTIDADES) NUM_ENTIDADES--COUNT(CASE WHEN CC.CVE_SITUACION IN (1,3,4,5,6) THEN 1 ELSE 0 END) NUM_ENTIDADES /*PARA EL CONTEO SOLO SE TOMAN EN CUENTA LAS SITUACIONES DE DEUDA DIRECTA*/
          ,SUM(ENT_CON_ATRASO) ENT_CON_ATRASO
          /*FIN PR-283*/
          ,SUM(VIGENTE) VIGENTE
          ,SUM(REESTRUCTURADO) REESTRUCTURADO
          ,SUM(REFINANCIADO) REFINANCIADO
          ,SUM(VENCIDO) VENCIDO
          ,SUM(JUDICIAL) JUDICIAL
          ,SUM(INTERESES) INTERESES
          ,SUM(SALDO_MN) SALDO_MN
          ,SUM (IMP_MTO_SALDO) IMP_MTO_SALDO
          ,SUM(ES_INTERES) ES_INTERES
          ,DECODE(CVE_PRODUCTO ,'TJ',1,0) OrdenProducto /*OrdenamientoProducto*/
          ,MAX(CASE WHEN CVE_TIPO_CREDITO='CC' AND CVE_PRODUCTO='TJ' THEN
                  (SELECT SUM(TOT_DEUDA_DIRECTA) 
                      FROM TMP_RESUMEN_CREDITO OC 
                  WHERE CVE_TIPO_CREDITO='CC' AND CVE_PRODUCTO='LC')
              ELSE 0
              END
          ) LINEA_CREDITO
      FROM (

            SELECT   
                CC.CVE_TIPO_CREDITO
                ,CC.CVE_PRODUCTO   
                ,MAX(CC.FEC_MAXIMA) FECHA_REPORTE_SBS
                ,MAX(CASE WHEN CC.FEC_MAXIMA=FEC_CARGA_RCC THEN CC.CALIFICACION
                    ELSE 9 END) CALIFICACION /*SI NO APARECE EN LA /LTIMA CARGA, LA CUENTA ESTA CERRADA*/
                ,MAX(CC.MAX_MOROSIDAD_12) MAX_MOROSIDAD_12
                ,MAX(C_PROD.DES_TIPO_CREDITO) DES_TIPO_CREDITO
                ,MAX(C_PROD.DES_PRODUCTO) DES_PRODUCTO
                ,MAX(CAN_CON_DIAS)  MAX_MOROSIDAD_ACTUAL
                ,MAX(MONTHS_BETWEEN(FEC_CARGA_RCC,ADD_MONTHS(FEC_MINIMA,-1) )) ANTIGUEDAD
                /*INICIA PR-283*/
                ,CASE WHEN MAX(CAN_CON_DIAS) > 0 AND MIN(CC.CVE_SITUACION) NOT IN(8,9)  THEN 1 ELSE 0 END  ENT_CON_ATRASO
                /*FIN PR-283*/
                ,SUM(DECODE(CC.CVE_SITUACION,1,IMP_MTO_SALDO,0)) VIGENTE
                ,SUM(DECODE(CC.CVE_SITUACION,3,IMP_MTO_SALDO,0)) REESTRUCTURADO
                ,SUM(DECODE(CC.CVE_SITUACION,4,IMP_MTO_SALDO,0)) REFINANCIADO
                ,SUM(DECODE(CC.CVE_SITUACION,5,IMP_MTO_SALDO,0)) VENCIDO
                ,SUM(DECODE(CC.CVE_SITUACION,6,IMP_MTO_SALDO,0)) JUDICIAL
                ,SUM(DECODE(CC.CVE_SITUACION,8,IMP_MTO_SALDO,0)) INTERESES
                ,SUM(DECODE(CC.CVE_SITUACION,10,IMP_MTO_SALDO,0)) SALDO_MN
                ,SUM (IMP_MTO_SALDO) IMP_MTO_SALDO
                ,SUM(ES_INTERES) ES_INTERES
                ,CASE WHEN MIN(CC.CVE_SITUACION) NOT IN(8,9)  THEN 1 ELSE 0 END NUM_ENTIDADES 
            FROM (
                SELECT  /*INFO HISTORICA*/
                    CVE_TIPO_CREDITO
                    ,CVE_PRODUCTO
                    ,CVE_EMPRESA
                    ,CAN_CON_DIAS
                    ,FEC_PERIODO
                    ,CVE_RUBRO
                    ,CVE_TIPO
                    ,CVE_MODALIDAD
                    ,CALIFICACION
                    ,CVE_SUBMODALIDAD
                    ,CVE_SITUACION
                    ,IMP_MTO_SALDO 
                    ,MIN(FEC_PERIODO) OVER (PARTITION BY CVE_TIPO_CREDITO,CVE_PRODUCTO) FEC_MINIMA
                    ,MAX(FEC_PERIODO) OVER (PARTITION BY CVE_TIPO_CREDITO,CVE_PRODUCTO) FEC_MAXIMA
                    ,MAX(CASE WHEN FEC_PERIODO BETWEEN ADD_MONTHS(FE.FEC_CARGA_RCC,-24)  AND FE.FEC_CARGA_RCC
                        THEN CAN_CON_DIAS
                    ELSE 0 END) OVER (PARTITION BY CVE_TIPO_CREDITO,CVE_PRODUCTO) MAX_MOROSIDAD_12
                    ,FEC_CARGA_RCC
                    ,ES_INTERES
                FROM PRE_CONSOLIDADO_CUENTAS_RCC
                CROSS JOIN FECHAS_ENTIDADES FE
                /*INICIA PR-283 --FILTRA SITUACION POR DEUDA AL DIA, DEUDA MOROSA Y RENDIMIENTOS DEVENGADOS--*/
                WHERE CVE_SITUACION IN (1,3,4,5,6,8,10)
                /*FIN PR-283*/
                ) CC 

            INNER JOIN GPC_PRODUCTO_AGRUPAMIENTO C_PROD /*OBTENER ETIQUETAS DE PRODUCTO Y TIPO_PRODUCTO*/
                ON C_PROD.CVE_TIPO_CREDITO=CC.CVE_TIPO_CREDITO
                AND C_PROD.CVE_PRODUCTO=CC.CVE_PRODUCTO
            WHERE CC.CVE_PRODUCTO IS NOT NULL /*REGISTROS NO NECESARIOS SON NULOS*/
             AND CC.FEC_MAXIMA=CC.FEC_PERIODO /*SOLO SE OBTIENE INFO MAXIMA FECHA*/
          GROUP BY 
           CC.CVE_TIPO_CREDITO
           ,CC.CVE_PRODUCTO
            ,CVE_EMPRESA

          )
          GROUP BY            
            CVE_TIPO_CREDITO
           ,CVE_PRODUCTO          

           )
           )

           SELECT 
        (CASE WHEN OrdenFuente=1 AND CVE_TIPO_CREDITO='CC' AND CVE_PRODUCTO='TJ'
            THEN 2 
            ELSE 4 END) TIPO_TARJETA /*-1. /nicamente TC -2. Grande sin LC -3. Chica*/
        ,CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE_SBS
        ,VIGENTE+REESTRUCTURADO+REFINANCIADO+VENCIDO+JUDICIAL TOT_DEUDA_DIRECTA
        ,CALIFICACION IDCALIFICACION
        ,DES_CALIFICACION CALIFICACION
        ,MAX_MOROSIDAD_12
        ,MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,JUDICIAL
        ,INTERESES
        ,(CASE WHEN VENCIDO>0 AND JUDICIAL>0
            THEN (VENCIDO+JUDICIAL)/DECODE(VIGENTE+REESTRUCTURADO+REFINANCIADO+VENCIDO+JUDICIAL,0,0,VIGENTE+REESTRUCTURADO+REFINANCIADO+VENCIDO+JUDICIAL)
            ELSE 0 END) PCT_MOROSA
        ,DECODE(SALDO_MN,0,0,((SALDO_MN/VIGENTE+REESTRUCTURADO+REFINANCIADO+VENCIDO+JUDICIAL)*100))  PCT_MONEDA_EXTRANJERA
        ,0 DEUDA_INDIRECTA /*PARA RCC NO SE REQUIERE INDIRECTA*/
        ,LINEA_CREDITO LINEA_CREDITO
        ,VIGENTE+REESTRUCTURADO+REFINANCIADO DEUDA_CORRIENTE
        ,VENCIDO+JUDICIAL DEUDA_MOROSA
    ,p_NUM_PERSONA
    ,ES_INTERES
    ,v_numRegistro
    FROM CONSOLIDADO_CUENTAS_RCC;

    /*****************FIN CUENTAS DE LA RCC***************************/
COMMIT;
   
    /*****************INICIO MICROFINANZAS ***************************/
    INSERT INTO  TMP_RESUMEN_CREDITO
        ( 
        CVE_TIPO_TARJETA
        ,CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE
        ,TOT_DEUDA_DIRECTA
        ,IDCALIFICACION
        ,CALIFICACION
        ,MAX_MOROSIDAD_12
        ,MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,VENCIDA_MENOR_30 --PR-372
        ,VENCIDA_MAYOR_30 --PR-372
        ,JUDICIAL
        ,INTERESES
        ,PCT_MOROSA
        ,PCT_MONEDA_EXTRANJERA
        ,DEUDA_INDIRECTA
        ,LINEA_CREDITO
        ,DEUDA_CORRIENTE
        ,DEUDA_MOROSA
        ,NUM_PERSONA
        ,ES_INTERES
        ,NUMERO_REGISTRO)

WITH FECHAS_ENTIDADES AS (
    SELECT    /*+ ALL_ROWS */

        LAST_DAY(NVL(MAX(DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('MICROFINANZAS'),FEC_PERIODO,NULL)),TRUNC(SYSDATE))) FEC_CARGA_MICRO
     FROM GPT_CARGA_LOTES
     WHERE
     FEC_CANCELACION IS NULL
     AND        CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('MICROFINANZAS') FROM DUAL)
     AND  FEC_PERIODO >=  (SELECT LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE),-24)) + 1 FROM DUAL)       

)
, CONSOLIDADO_MICROFINANZAS AS
    (
 SELECT  --IMPLEMENTACIvìN DE LA HISTORIA PR-372
        TIPO_TARJETA
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE
        ,TOT_DEUDA_DIRECTA
        ,IDCALIFICACION
        ,DECODE(IDCALIFICACION,7,'SIN CALIFICACIÓN',
                            (SELECT I.DES_CLASIFICACION 
                            FROM GPC_CLASIFICACION I 
                            WHERE I.CVE_CLASIFICACION = IDCALIFICACION)
                            )  CALIFICACION
        ,MAX_MOROSIDAD_12
        ,MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,VENCIDA_MENOR_30 --PR-372
        ,VENCIDA_MAYOR_30 --PR-372
        ,JUDICIAL
        ,INTERESES
        ,ROUND((TOT_DEUDA_MOROSA*100)/TOT_DEUDA_DIRECTA,0) PCT_MOROSA --PR-372
        ,ROUND((TOT_DEUDA_ME*100)/TOT_DEUDA_DIRECTA,0) PCT_MONEDA_EXTRANJERA --PR-372
        ,DEUDA_INDIRECTA --DEUDA INDIRECTA
        ,LINEA_CREDITO
        ,DEUDA_CORRIENTE --PR-270
        ,DEUDA_MOROSA
        FROM 
            (
             SELECT  
                    1 TIPO_TARJETA/*TARJETA GRANDE CON LINEA DE CREDITO*/
                    ,'Microfinanzas no supervisadas' DES_PRODUCTO
                    ,'MCF' CVE_TIPO_CREDITO
                    ,'Microfinanzas no supervisadas' DES_TIPO_CREDITO
                    ,LAST_DAY(MAX(MAXFECPERIODO)) FECHA_REPORTE
                    ,SUM(VIGENTE) +  SUM(REFINANCIADO) + SUM(VENCIDA_MENOR_30) + SUM(VENCIDA_MAYOR_30) + SUM(CJUDICIAL) TOT_DEUDA_DIRECTA --PR-372 SE AGREGA EL SUM DE DEUDA VENCIDA MENOR Y MAYOR 30 DIAS.
                    ,CASE WHEN (MAX(ES_ACTUAL) = 1) THEN DECODE(MAX(CVE_CLASIFICACION),-1,7,MAX(CVE_CLASIFICACION)) ELSE 9 END IDCALIFICACION --SI LA CALIFICACIvìN ES -1 EN TODAS LAS ENTIDADES DE LA PERSONA SIGNIFICA QUE ES SIN CALIFICACIvìN(7)
                    ,MAX(DIASATRASO24)     MAX_MOROSIDAD_12                --PEOR MOROSIDAD ULTIMOS 24 MESES PR-372
                    ,MAX(DIASATRASOACTUAL)   MAX_MOROSIDAD_ACTUAL               --PEOR MOROSIDAD ACTUAL
                    ,DECODE(MIN(ANTIGUEDAD),NULL,0,MONTHS_BETWEEN(LAST_DAY(MAX(MAXFECPERIODO)),LAST_DAY(MIN(ANTIGUEDAD))) + 1 )  ANTIGUEDAD -- EXPRESADA EN MESES, EL MINIMO DE TODAS LAS ENTIDADES CONTRA EL MAXIMO DE TODAS LAS ENTIDADES DE LA PERSONA
                    ,SUM(CASE WHEN ES_ACTUAL = 1 THEN 1 ELSE 0 END) NUM_ENTIDADES --NUMERO DE EMPRESAS DE LA PERSONA EN EL ULTIMO MES REPORTADO DE LA ENTIDAD
                    ,SUM(CASE WHEN ES_ACTUAL = 1 AND DIASATRASOACTUAL > 0 THEN 1 ELSE 0 END)     ENT_CON_ATRASO            -- NUMERO EMPRESAS CON ATRASO
                    ,SUM(VIGENTE) VIGENTE --VIGENTE
                    --Inicio PR-372
                    ,0 REESTRUCTURADO --REESTRUCTURADA
                    ,SUM(REFINANCIADO) REFINANCIADO --REFINANCIADA --PR-372
                    ,0 VENCIDO --VENCIDOS
                    ,SUM(VENCIDA_MENOR_30) VENCIDA_MENOR_30 --PR-372
                    ,SUM(VENCIDA_MAYOR_30) VENCIDA_MAYOR_30 --PR-372
                    --Fin PR-372
                    ,SUM(CJUDICIAL) JUDICIAL --COBRANZA JUDICIAL
                    ,0 INTERESES
                    ,SUM(VENCIDA_MENOR_30) + SUM(VENCIDA_MAYOR_30) + SUM(CJUDICIAL) TOT_DEUDA_MOROSA
                    ,SUM(SALDO_ME_MN) TOT_DEUDA_ME
                    ,0 DEUDA_INDIRECTA --DEUDA INDIRECTA
                    ,0 LINEA_CREDITO
                    ,SUM(VIGENTE) + SUM(REFINANCIADO) DEUDA_CORRIENTE --PR-270 /*SE VALIDO LA SUMA PARA MICRO PR-277*/
                    /*INICIA PR-278 Deuda Directa Vencida menor o igual a 30 dv¿as +Deuda Directa Vencida mayor a 30 dv¿as +Deuda Directa Cobranza Judicial*/
                    ,SUM(VENCIDA_MENOR_30) + SUM(VENCIDA_MAYOR_30) + SUM(CJUDICIAL) DEUDA_MOROSA
                    /*FIN PR-278*/
                FROM  
                    (
                    SELECT   
                            IDPRODUCTO
                            ,CVE_ENTIDAD
                            ,MIN(MINFECPERIODO)  ANTIGUEDAD /*NO CONSIDERAR LAS FECHAS DE DEUDA INDIRECTA */
                            ,MAX(MAXFECPERIODO)  MAXFECPERIODO
                            ,MAX(DIASATRASOACTUAL)   DIASATRASOACTUAL            --PEOR MOROSIDAD ACTUAL
                            ,MAX(DIASATRASO24)     DIASATRASO24                 --PEOR MOROSIDAD ULTIMOS 24 MESES PR-372
                            ,SUM(D_VIGENTE) VIGENTE --DEUDA DIRECTA VIGENTE
                            ,SUM(D_REFINANCIADA) REFINANCIADO --DEUDA DIRECTA REFINANCIADO
                            ,SUM(D_MENOR30) VENCIDA_MENOR_30 --VENCIDA DIRECTA MENOR O IGUAL A 30 DIAS 
                            ,SUM(D_MAYOR30) VENCIDA_MAYOR_30 --VENCIDA DIRECTA MAYOR A 30 DIAS 
                            ,SUM(D_JUDICIAL) CJUDICIAL --DEUDA DIRECTA COBRANZA JUDICIAL
                            ,SUM(SALDO_ME_MN) SALDO_ME_MN    /* DEUDA EN MONEDA EXTRANJERA, SIN CONSIDERAR  DEUDA INDIRECTA */
                            ,MAX(FEC_CARGA_MICRO) FEC_CARGA_MICRO
                            ,MAX(CVE_CLASIFICACION) CVE_CLASIFICACION
                            ,MAX(ES_ACTUAL) ES_ACTUAL
                        FROM
                            (                                        
                            SELECT 
                                    'MNR' IDPRODUCTO
                                    ,INFO_BASE.CVE_ENTIDAD 
                                    ,INFO_BASE.MIN_FEC_PERIODO_ENTIDAD  MINFECPERIODO
                                    ,INFO_BASE.MAX_FEC_PERIODO_ENTIDAD  MAXFECPERIODO
                                    ,MAX(INFO_BASE.CAN_NUM_DIAS_VEN) DIASATRASOACTUAL
                                    ,MAX(CASE WHEN INFO_BASE.FEC_PERIODO >= LAST_DAY(ADD_MONTHS(INFO_BASE.MAX_FEC_PERIODO_ENTIDAD,-24)) + 1 THEN CAN_NUM_DIAS_VEN ELSE 0 END)  DIASATRASO24             -- PR 372 PEOR CALIFICACION ACTUAL
                                    ,SUM(ROUND(INFO_BASE.D_VIGENTE,2)) D_VIGENTE 
                                    ,SUM(ROUND(INFO_BASE.D_REFINANCIADA,2)) D_REFINANCIADA 
                                    ,SUM(ROUND(INFO_BASE.D_MENOR30,2)) D_MENOR30 
                                    ,SUM(ROUND(INFO_BASE.D_MAYOR30,2)) D_MAYOR30 
                                    ,SUM(ROUND(INFO_BASE.D_JUDICIAL,2)) D_JUDICIAL 
                                    ,SUM(DECODE(INFO_BASE.CVE_MONEDA,10,0,ROUND(INFO_BASE.IMP_SALDO,2))) SALDO_ME_MN 
                                    ,MAX(FEC_CARGA_MICRO) FEC_CARGA_MICRO
                                    ,MAX(INFO_BASE.CVE_CLASIFICACION) CVE_CLASIFICACION
                                    ,MAX(INFO_BASE.ES_ACTUAL) ES_ACTUAL
                                FROM (
                                        SELECT  CVE_ENTIDAD
                                                ,FEC_PERIODO
                                                ,CVE_MONEDA
                                                ,MAX(MAX_FEC_PERIODO_ENTIDAD) MAX_FEC_PERIODO_ENTIDAD
                                                ,MIN(MIN_FEC_PERIODO_ENTIDAD) MIN_FEC_PERIODO_ENTIDAD
                                                ,MAX(FEC_PERIODO_LOTE) FEC_PERIODO_LOTE
                                                ,MAX(CAN_NUM_DIAS_VEN) CAN_NUM_DIAS_VEN
                                                ,MAX(LAST_DAY_FEC_PERIODO) LAST_DAY_FEC_PERIODO
                                                ,MAX(FEC_CARGA_MICRO) FEC_CARGA_MICRO
                                                ,CASE WHEN SUM(D_MENOR30) = SUM(D_VIGENTE) OR SUM(D_MAYOR30) = SUM(D_VIGENTE) --PR-372 Regla para descargar el saldo vigente si viene el mismo monto en deuda mayor/menor a 30 dias 
                                                        THEN SUM(IMP_SALDO) - SUM(D_VIGENTE) --le restamos lo vigente (Para obtener el saldo total por tipo de moneda menos lo vigente)
                                                    ELSE
                                                        SUM(IMP_SALDO) --Para obtener el saldo total por tipo de moneda.
                                                END IMP_SALDO
                                                ,CASE WHEN SUM(D_MENOR30) = SUM(D_VIGENTE) OR SUM(D_MAYOR30) = SUM(D_VIGENTE) --PR-372 Regla para descargar el saldo vigente si viene el mismo monto en deuda mayor/menor a 30 dias 
                                                    THEN 0
                                                ELSE
                                                    SUM(D_VIGENTE)
                                                END D_VIGENTE
                                                ,SUM(D_REFINANCIADA) D_REFINANCIADA
                                                ,SUM(D_MENOR30) D_MENOR30
                                                ,SUM(D_MAYOR30) D_MAYOR30
                                                ,SUM(D_JUDICIAL) D_JUDICIAL
                                                ,MAX(CVE_CLASIFICACION) CVE_CLASIFICACION
                                                ,MAX(ES_ACTUAL) ES_ACTUAL
                                        FROM (
                                                SELECT  CVE_ENTIDAD
                                                    ,MAX_FEC_PERIODO_ENTIDAD
                                                    ,MIN_FEC_PERIODO_ENTIDAD
                                                    ,FEC_PERIODO
                                                    ,FEC_PERIODO_LOTE
                                                    ,IMP_SALDO
                                                    ,CAN_NUM_DIAS_VEN
                                                    ,CVE_MONEDA
                                                    ,CVE_TIPO_SALDO
                                                    ,LAST_DAY_FEC_PERIODO
                                                    ,NUM_LOTE_CARGA
                                                    ,FEC_CARGA_MICRO
                                                    ,D_VIGENTE
                                                    ,D_REFINANCIADA
                                                    ,D_MENOR30
                                                    ,D_MAYOR30
                                                    ,D_JUDICIAL
                                                    ,CVE_CLASIFICACION
                                                    ,ES_ACTUAL
                                                    FROM (
                                                        SELECT  
                                                                VIS.CVE_ENTIDAD
                                                                ,VIS.MAX_FEC_ENTIDAD MAX_FEC_PERIODO_ENTIDAD
                                                                ,VIS.MIN_FEC_ENTIDAD MIN_FEC_PERIODO_ENTIDAD
                                                                ,VIS.FEC_PERIODO
                                                                ,CL.FEC_PERIODO       FEC_PERIODO_LOTE                
                                                                ,CASE WHEN VIS.CVE_TIPO_SALDO IN (2,3,4,5,6)
                                                                    THEN VIS.IMP_SALDO
                                                                    ELSE
                                                                        0
                                                                END IMP_SALDO --SOLO CONSIDERAR LAS DEUDAS: VIGENTE, REFINANCIADA, MENOR Y MAYOR A 30 DIAS Y JUDICIAL
                                                                ,VIS.CAN_NUM_DIAS_VEN
                                                                ,VIS.CVE_MONEDA
                                                                ,VIS.CVE_TIPO_SALDO
                                                                ,LAST_DAY(MAX(VIS.FEC_PERIODO) OVER (PARTITION BY VIS.CVE_ENTIDAD)) LAST_DAY_FEC_PERIODO --PR-372
                                                                ,VIS.NUM_LOTE_CARGA
                                                                ,FE.FEC_CARGA_MICRO
                                                                --INICIO PR-372
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,2,VIS.IMP_SALDO),0) D_VIGENTE
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,3,VIS.IMP_SALDO),0) D_REFINANCIADA
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,4,VIS.IMP_SALDO),0) D_MENOR30
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,5,VIS.IMP_SALDO),0) D_MAYOR30
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,6,VIS.IMP_SALDO),0) D_JUDICIAL
                                                                ,CASE   WHEN CAL.POR_CALIFICACION_DEUDA_4 > 0 
                                                                            THEN 4
                                                                        WHEN CAL.POR_CALIFICACION_DEUDA_3 > 0
                                                                            THEN 3
                                                                        WHEN CAL.POR_CALIFICACION_DEUDA_2 > 0
                                                                            THEN 2
                                                                        WHEN CAL.POR_CALIFICACION_DEUDA_1 > 0
                                                                            THEN 1
                                                                        WHEN CAL.POR_CALIFICACION_DEUDA_0 > 0
                                                                            THEN 0
                                                                        ELSE -1
                                                                END CVE_CLASIFICACION --SI EL CALCULO DEVUELVE -1 SIGNIFICA QUE TODAS LAS CALIFICACIONES VIENEN EN 0 Y ES SIN CALIFICACIvìN (7)
                                                                ,VIS.ES_ACTUAL
                                                                --FIN PR-372
                                                        FROM TABLE(GPPG_RC_DELTA.GET_DATOS_VISIBLES_MICRO(p_NUM_PERSONA)) VIS
                                                                INNER JOIN GPT_CARGA_LOTES CL
                                                                        ON VIS.NUM_LOTE_CARGA = CL.NUM_LOTE_CARGA
                                                                INNER JOIN GPT_CALIFICA_PERSONA_MICRO CAL
                                                                        ON VIS.NUM_PERSONA = CAL.NUM_PERSONA
                                                                        AND VIS.CVE_ENTIDAD = CAL.CVE_ENTIDAD
                                                                        AND VIS.FEC_PERIODO = CAL.FEC_PERIODO
                                                                CROSS JOIN FECHAS_ENTIDADES FE
                                                        )
                                            )
                                            GROUP BY FEC_PERIODO
                                                    ,CVE_ENTIDAD
                                                    ,CVE_MONEDA                                          
                                        ) INFO_BASE
                                 GROUP BY  INFO_BASE.CVE_ENTIDAD
                                          ,INFO_BASE.MIN_FEC_PERIODO_ENTIDAD 
                                          ,INFO_BASE.MAX_FEC_PERIODO_ENTIDAD 
                                          ,INFO_BASE.CVE_MONEDA
                                          ,INFO_BASE.FEC_PERIODO
                            )
                        GROUP BY  IDPRODUCTO
                                ,CVE_ENTIDAD
                    ) INFO_MICRO
                GROUP BY IDPRODUCTO
            )
        WHERE TOT_DEUDA_DIRECTA > 0 --PR-281

)SELECT
        TIPO_TARJETA
        ,CVE_TIPO_CREDITO CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE
        ,TOT_DEUDA_DIRECTA
        ,IDCALIFICACION
        ,CALIFICACION
        ,MAX_MOROSIDAD_12
        ,MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,VENCIDA_MENOR_30 --PR-372
        ,VENCIDA_MAYOR_30 --PR-372
        ,JUDICIAL
        ,INTERESES
        ,PCT_MOROSA
        ,PCT_MONEDA_EXTRANJERA
        ,DEUDA_INDIRECTA
        ,LINEA_CREDITO
        ,DEUDA_CORRIENTE
        ,DEUDA_MOROSA
        ,p_NUM_PERSONA
        ,0 ES_INTERES
        ,v_numRegistro
    FROM    CONSOLIDADO_MICROFINANZAS;
    /*****************FIN MICROFINANZAS *****************************/

COMMIT;

 /******************************** INICIO NEGATIVA *****************************/
     INSERT INTO  TMP_RESUMEN_CREDITO
        ( 
        CVE_TIPO_TARJETA
        ,CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE
        ,TOT_DEUDA_DIRECTA
        ,IDCALIFICACION
        ,CALIFICACION
        ,MAX_MOROSIDAD_12
        ,MAX_MOROSIDAD_ACTUAL
        ,ANTIGUEDAD
        ,NUM_ENTIDADES
        ,ENT_CON_ATRASO
        ,VIGENTE
        ,REESTRUCTURADO
        ,REFINANCIADO
        ,VENCIDO
        ,JUDICIAL
        ,INTERESES
        ,PCT_MOROSA
        ,PCT_MONEDA_EXTRANJERA
        ,DEUDA_INDIRECTA
        ,LINEA_CREDITO
        ,DEUDA_CORRIENTE
        ,DEUDA_MOROSA
        ,NUM_PERSONA
        ,ES_INTERES
                ,NUMERO_REGISTRO)

  WITH FECHAS_ENTIDADES AS (
      SELECT    /*+ ALL_ROWS */

                LAST_DAY(NVL(MAX(DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('MOROSIDAD'),FEC_PERIODO,NULL)),TRUNC(SYSDATE))) FEC_CARGA_MORO
                ,LAST_DAY(NVL(MAX(DECODE(CVE_ENTIDAD,GPPG_RC.get_entidad('SBS'),DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('RCC'),FEC_PERIODO,NULL),NULL)),TRUNC(SYSDATE))) FEC_CARGA_RCC
                ,LAST_DAY(NVL(MAX(DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('PROTESTOS'),FEC_PERIODO,NULL)),TRUNC(SYSDATE)))FEC_CARGA_PROT --ULTIMA CARGA PROTESTO 
                ,LAST_DAY(NVL(MAX(DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('MICROFINANZAS'),FEC_PERIODO,NULL)),TRUNC(SYSDATE))) FEC_CARGA_MICRO
                ,LAST_DAY(NVL(MAX(DECODE(CVE_ENTIDAD,GPPG_RC.get_entidad('SUNAT'),DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('DEUDORES'),FEC_PERIODO,NULL),NULL)),TRUNC(SYSDATE))) FEC_CARGA_SUNAT 
                ,MAX(DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('DEUDORES'),FEC_PERIODO,NULL)) FEC_PERIODO_GLOBAL_ENTIDAD -- FEC_PERIODO_GLOBAL_DEUDORES
                ,LAST_DAY(NVL(MAX(DECODE(CVE_TIPO_FUENTE,GPPG_RC.get_fuente('AFP'),FEC_PERIODO,NULL)),TRUNC(SYSDATE))) FEC_CARGA_AFP
                ,TRUNC(SYSDATE) FEC_CONSULTA
                ,LAST_DAY(TRUNC(SYSDATE)) FEC_LASTDAYCONSULTA /* FECHA DE CONSULTA A ULTIMO DIA DE MES */
                ,LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE),-1)) FEC_TIPO_CAMBIO /* PARA EL TIPO DE CAMBIO */
         FROM GPT_CARGA_LOTES
         WHERE
         FEC_CANCELACION IS NULL
         AND  (

              (
              CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('MOROSIDAD') FROM DUAL)
              )                 
              OR
              (
              CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('PROTESTOS') FROM DUAL)
              )    
              OR
              (
                  (
                    CVE_ENTIDAD = (SELECT GPPG_RC.get_entidad('SBS') FROM DUAL)
                    AND  CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('RCC') FROM DUAL)
                  )               
              )
              OR
                (
                    CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('MICROFINANZAS') FROM DUAL)
                )
              OR
                (
                 (CVE_ENTIDAD = (SELECT GPPG_RC.get_entidad('SUNAT') FROM DUAL)
                  AND  CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('DEUDORES') FROM DUAL)
                  )                 
                )
              OR
                (
                    CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('AFP') FROM DUAL)
                )
            )
         AND  FEC_PERIODO >=  (SELECT LAST_DAY(ADD_MONTHS(TRUNC(SYSDATE),-24)) + 1 FROM DUAL)       
    )
,PRE_CONSOLIDADO_PROTESTOS AS 
        (
        --  NEG- PROTESTOS  
        SELECT  
                 IDPRODUCTO CVE_PRODUCTO
                 ,'Negativa' DES_PRODUCTO
                 ,'PRO' CVE_TIPO_CREDITO
                 ,'Protestos' DES_TIPO_CREDITO
                 ,CLASIFICACION
                 ,NUMEROEMP
                 ,0  NOEMPATRASO -- N/A PARA NEGATIVA 
                 ,ROUND(DECODE(DIASATRASOACTUAL,NULL,0,FEC_CONSULTA - DIASATRASOACTUAL),0) DIASATRASOACTUAL
                 ,0  DIASATRASODOCE  --  N/A PARA NEGATIVA, PARA PROTESTOS LA MAXIMA MORIDAD ACTUAL SERvø SIEMPRE LA MAXIMA MOROSIDAD DEL PERIODO DE CONSULATA 
                 ,MONTHS_BETWEEN(FEC_LASTDAYCONSULTA, LAST_DAY(ANTIGUEDAD)) + 1 ANTIGUEDAD
                 ,MAXFECPERIODO
                 , DEUDADIRECTA 
                 ,0 VIGENTE
                 ,0 REESTRUCTURADO
                 ,DEUDADIRECTA VENCIDOS
                 ,0 CJUDICIAL
                 ,0 PORCVENCIDA
                 ,0 PORCME
                 ,0 DEUDAINDIRECTA
                 ,SALDO_ME_MN --PR-276
        FROM
            (
            -- 1-OBTENEMOS DETALLE DE PROTESTOS 
            SELECT 'NEG' IDPRODUCTO
                    ,MAX(DECODE(CVE_ESTATUS,1,DECODE(vPRO.SITUACION,1,6,2,6,5),5)) CLASIFICACION --6 REGISTRO MOROS0 Y 5 REGISTRO CERRADO 
                    ,SUM(DECODE(CVE_ESTATUS,1,DECODE(vPRO.SITUACION,1,1,2,1,0),0)) NUMEROEMP --6 REGISTRO MOROS0 Y 5 REGISTRO CERRADO 
                    ,MIN(DECODE(CVE_ESTATUS,1,DECODE(vPRO.SITUACION,1,FEC_VENCIMIENTO,2,FEC_VENCIMIENTO,NULL),NULL)) DIASATRASOACTUAL 
                    ,MIN(vPRO.FEC_PROTESTO) ANTIGUEDAD
                    ,MAX(vPRO.FEC_PERIODO)  MAXFECPERIODO
                    -- DEUDA DIRECTA IGUAL A DEUDA VENCIDA 
                    ,SUM(
                        DECODE(CVE_ESTATUS,1,
                                DECODE(
                                      DECODE(vPRO.SITUACION,1,1,2,1,0)
                                             ,1
                                             ,ROUND(vPRO.IMP_SALDO * TC.MON_UNIDAD,2)
                                             ,0)
                               ,0)  
                         ) DEUDADIRECTA  
                    ,MAX(FEC_CONSULTA) FEC_CONSULTA
                    ,MAX(FEC_LASTDAYCONSULTA) FEC_LASTDAYCONSULTA
                    ,SUM(
                        DECODE(CVE_ESTATUS,1,
                                DECODE(
                                      DECODE(vPRO.SITUACION,1,1,2,1,0)
                                             ,1
                                             ,DECODE(vPRO.CVE_MONEDA,10,0,ROUND(vPRO.IMP_SALDO * TC.MON_UNIDAD,2))
                                             ,0)
                               ,0)  
                         )SALDO_ME_MN --PR-276
            FROM     
                (
                 -- 1  DETERMINAMOS LA FECHA MAXIMA DEL PERIODO 
                 -- PUEDEN EXISTIR REGISTROS EN A Y M QUE NO APARECEN EN LA CARGA ANUAL 
                 SELECT 
                        CVE_MONEDA
                       ,IMP_SALDO
                       ,FEC_PROTESTO
                       ,FEC_PERIODO
                       ,CVE_PROCESO
                       ,CVE_ESTATUS
                       ,SITUACION
                       ,DECODE(FEC_VENCIMIENTO,NULL,FEC_PROTESTO,FEC_VENCIMIENTO) FEC_VENCIMIENTO
                       ,MAXSITUACION
                       ,FEC_CONSULTA
                       ,FEC_LASTDAYCONSULTA
                       ,LAST_DAY(FEC_ANOMES_FILE) LASTDAY_FEC_ANOMES_FILE --PR-276
                 FROM
                    (
                    SELECT  
                            -- HOMOLOGAMOS CONSULTA PARA OBTENER LOS BENEFICIOS DE LA CONSULTA EN MEMORIA 
                            PRO.NUM_SECUENCIA
                            ,PRO.CVE_TIPO_REGISTRO
                            ,DECODE(PRO.FEC_REGULARIZACION,NULL,PRO.CVE_PROCESO,'R') CVE_PROCESO
                            ,SG.CVE_MONEDA
                            ,SG.IMP_SALDO
                            ,PRO.FEC_VENCIMIENTO
                            ,PRO.FEC_PROTESTO
                            ,PRO.FEC_REGULARIZACION
                            ,SG.FEC_PERIODO
                            ,PRO.FEC_EMISION_MODIFICACION
                            ,SG.CVE_ESTATUS
                            ,DECODE(DECODE(PRO.FEC_REGULARIZACION,NULL,PRO.CVE_PROCESO,'R'),'A',1,'M',2,'R',3,'C',4,5) SITUACION -- (ELIMINACION =  5 )   -- A=ALTA, M=MODIFICACION, R=REGULADO, C=CANCELADO, E=ANULADO 
                            ,MAX(DECODE(DECODE(PRO.FEC_REGULARIZACION,NULL,PRO.CVE_PROCESO,'R'),'A',1,'M',2,'R',3,'C',4,5)) OVER (PARTITION BY PRO.NUM_SECUENCIA,PRO.CVE_TIPO_REGISTRO) MAXSITUACION
                            ,MAX(SG.FEC_PERIODO) OVER (PARTITION BY PRO.NUM_SECUENCIA,PRO.CVE_TIPO_REGISTRO) MAX_FECPERIODO
                            ,MAX(SG.NUM_SALDO) OVER (PARTITION BY PRO.NUM_SECUENCIA,PRO.CVE_TIPO_REGISTRO, SG.FEC_PERIODO ) MAXNUM_SALDO
                            ,SG.NUM_SALDO 
                            ,PRO.CVE_TIPO_VALOR
                            ,PRO.NUM_PERSONA_GIRADOR
                            ,PRO.NOM_NOMBRE_GIRADOR
                            ,PRO.NUM_PERSONA      
                            ,FE.FEC_CARGA_PROT  
                            ,FE.FEC_CONSULTA
                            ,FE.FEC_LASTDAYCONSULTA
                            ,PRO.FEC_ANOMES_FILE
                    FROM GPT_PROTESTOS PRO 
                        INNER JOIN GPT_SALDOS_GENERALES SG
                                ON SG.NUM_SALDO = PRO.NUM_SALDO    
                                AND SG.NUM_PERSONA = PRO.NUM_PERSONA
                        CROSS JOIN FECHAS_ENTIDADES FE
                    WHERE  PRO.CVE_ESTATUS = 1  -- CARGA ANUAL 
                        AND PRO.FEC_ANOMES_FILE >= ADD_MONTHS(TRUNC(FE.FEC_LASTDAYCONSULTA,'YEAR'),-60) 
                        AND PRO.FEC_REGULARIZACION IS NULL --Solo los protestos no aclarados PR-276
                        AND PRO.NUM_PERSONA = p_NUM_PERSONA
                    )
                WHERE NUM_SALDO =  MAXNUM_SALDO
                    AND FEC_PERIODO = MAX_FECPERIODO
                    AND SITUACION =   MAXSITUACION
                    AND (
                            (MAXSITUACION BETWEEN 1 AND 2)   -- ACTIVOS Y  MODIFICADOS 
                            OR 
                            (MAXSITUACION =  3    -- REGULARIZADOS Y  CADUCOS 
                            AND FEC_ANOMES_FILE >=  ADD_MONTHS(TRUNC(FEC_LASTDAYCONSULTA,'YEAR'),-36)  -- REGLA DE EXCLUSION: 3 (tres) av±os, contados a partir del 1 de enero del av±o siguiente al de su anotaciv=n en el Registro   
                            )
                        ) 

                ) vPRO
                INNER JOIN 
(  --INICIO PR-276
                          SELECT  TO_NUMBER(CVE_MONEDA_ORIGEN) CVE_MONEDA_ORIGEN
                                , TO_NUMBER(CVE_MONEDA_DESTINO) CVE_MONEDA_DESTINO
                                ,MON_UNIDAD
                            FROM GPC_TIPO_CAMBIO GTC
                            INNER JOIN FECHAS_ENTIDADES FE
                                    ON GTC.FEC_PERIODO = FE.FEC_TIPO_CAMBIO
                          WHERE   GTC.CVE_MONEDA_DESTINO = 10
                          UNION
                           SELECT 10 CVE_MONEDA_ORIGEN
                                , 10 CVE_MONEDA_DESTINO
                                , 1 MON_UNIDAD
                          FROM GPC_TIPO_CAMBIO
                          --FIN PR-276
                          )  TC
                        ON TC.CVE_MONEDA_ORIGEN = vPRO.CVE_MONEDA 
                GROUP BY  'NEG'
                               -- 1-OBTENEMOS DETALLE DE PROTESTOS 
            )
                             -- NEG- PROTESTOS  
        )  

,PRE_CONSOLIDADO_MCOM AS (
--            NEG- MOROSIDAD COMERCIAL  
SELECT 
        IDPRODUCTO CVE_PRODUCTO
        ,'Negativa' DES_PRODUCTO
        ,'MCOM' CVE_TIPO_CREDITO
        ,'Morosidad Comercial' DES_TIPO_CREDITO
        ,CLASIFICACION --6 MOROSO,5 CERRADO
        ,NUMEROEMP
        --,NUMREG
        ,0 NOEMPATRASO
        ,ROUND(DECODE(MINFECVENACTUAL,NULL,0,FE.FEC_CONSULTA - MINFECVENACTUAL),0) DIASATRASOACTUAL  --EL DECODE DE  MINFECVENACTUAL = NULL ES PARA AQURLLOS CASOS QUE LA PERSONA SOLO APARECE  COMO DEUDA INDIRECTA 
        ,0 DIASATRASODOCE
        , MONTHS_BETWEEN(FE.FEC_CARGA_MORO, LAST_DAY(MINFECHAPERIODO)) + 1 ANTIGUEDAD
        , MAXFECHAPERIODO MAXFECPERIODO
        ,IMP_MTO_SALDO DEUDADIRECTA
        ,0 VIGENTE
        ,0 REESTRUCTURADO
        ,IMP_MTO_SALDO VENCIDOS
        ,0 CJUDICIAL
        ,0 PORCVENCIDA
        ,0 PORCME
        ,IMP_MTO_INDIRECTA DEUDAINDIRECTA
        ,0 SALDO_ME_MN
FROM
    (
          --4- OBTENEMOS INFORMACION REQUERIDA 
        SELECT 
                'NEG' IDPRODUCTO
                 --ClASIFICACION   6 REGISTRO MOROS0 Y 5 REGISTRO CERRADO 
                ,MAX(DECODE(vSG.CVE_TIPO_DEUDOR,1
                                                ,CASE WHEN ES_ACTUAL = 1  --Si el lote de carga es igual al del ultimo archivo cargado es actual
                                                    THEN 6 
                                                    ELSE 5 
                                                END
                            ,0)) CLASIFICACION --6 MOROSO,5 CERRADO

                -- PARA MOROSIDAD COMERCIAL SE CONSIDERA EL NUMERO DE REGISTROS EN EL ULTIMO PERIODO DE CARGA 
                ,SUM(DECODE(vSG.CVE_TIPO_DEUDOR,1
                                                ,1 
                                                ,0 
                            )) NUMREG   -- EL NUMERO DE REGISTROS 
                ,COUNT(DISTINCT(vSG.CVE_EMPRESA)) NUMEROEMP
                -- PEOR MOROSIDAD ACTUAL 
                ,MIN(DECODE(vSG.CVE_TIPO_DEUDOR,1
                                                     ,vSG.FEC_VENCIMIENTO 
                                                    ,NULL 
                            ))  MINFECVENACTUAL
                -- ANTIGUEDAD CONSIDERANDO TODOS LOS REGISROS DE DEUDA DIRECTA 
                ,MIN(DECODE(vSG.CVE_TIPO_DEUDOR,1,vSG.FEC_VENCIMIENTO,NULL))  ANTIGUEDAD
                ,MAX(MAX_FEC_PERIODO_ENTIDAD)   MAXFECHAPERIODO
                ,MIN(MIN_FEC_PERIODO_ENTIDAD)   MINFECHAPERIODO
                ,SUM(ROUND(vSG.IMP_SALDO * TC.MON_UNIDAD,2)) IMP_MTO_SALDO              
                ,SUM(DECODE(vSG.CVE_TIPO_DEUDOR,1,0)) IMP_MTO_INDIRECTA
        FROM 
                    (
                      -- DETALLE MOROSIDAD COMERCIAL 
                    SELECT  
                            DDMC.CVE_ENTIDAD  CVE_EMPRESA
                            ,FEC_PERIODO
                            ,LAST_DAY(FEC_PERIODO) LASTDAY_FEC_PERIODO
                            ,FEC_PERIODO_LOTE
                            ,CVE_MONEDA
                            ,IMP_SALDO
                            ,CVE_TIPO_DEUDOR
                            ,FEC_VENCIMIENTO
                             --LOS FECHAS MINIMAS DEBEN DETERMINARSE DESPUES DE LOS FILTROS DE EXCLUSIvìN *
                            ,MIN(FEC_PERIODO) OVER (PARTITION BY DDMC.CVE_ENTIDAD) MIN_FEC_PERIODO_ENTIDAD  --04/2013
                            ,MAX_FEC_PERIODO_ENTIDAD  -- SE UTILIZADA EN LA EVALUACION DE LA FECHA DE VENCIMIENTO 
                            ,MAX_FEC_REP_ADEUDO
                            ,MIN_FEC_REP_ADEUDO   -- SE UTILIZADA EN LA EVALUACION DE LA FECHA DE VENCIMIENTO 
                            ,NUM_LOTE_CARGA
                            ,ES_ACTUAL
                    FROM GPC_ENTIDAD_FUENTE EFU
                    INNER JOIN  (
                                SELECT
                                        CVE_ENTIDAD 
                                        ,FEC_PERIODO
                                        ,FEC_PERIODO_LOTE
                                        ,CVE_MONEDA
                                        ,IMP_SALDO
                                        ,CVE_TIPO_DEUDOR
                                        ,FEC_VENCIMIENTO 
                                        -- LOS FECHAS MAXIMAS DEBEN DETERMINARSE ANTES DE LOS FILTROS DE EXCLUSIvìN 
                                        ,MAX(FEC_PERIODO) OVER (PARTITION BY CVE_ENTIDAD) MAX_FEC_PERIODO_ENTIDAD
                                        -- IDENTIFICAR FECHA MAXIMA REPORTADA DEL ADEUDO 
                                        ,MAX(FEC_PERIODO) OVER (PARTITION BY CVE_ENTIDAD,FEC_VENCIMIENTO,CVE_MONEDA) MAX_FEC_REP_ADEUDO
                                        -- REF_CODIGO_MOROSO_ENT,CVE_TIPO_VALOR  NO SON CONSIDERADOS POR NO HABER CONSISTENCIA EN LOS DATOS 
                                        -- LA REGLA ESTA HOMOLOGADO CON FICO 
                                        ,MIN(FEC_PERIODO) OVER (PARTITION BY CVE_ENTIDAD,FEC_VENCIMIENTO,CVE_MONEDA) MIN_FEC_REP_ADEUDO  -- SE UTILIZADA EN LA EVALUACION DE LA FECHA DE VENCIMIENTO 
                                        ,FEC_CONSULTA
                                        ,FEC_CARGA_MORO
                                        ,NUM_LOTE_CARGA
                                        ,ES_ACTUAL
                                FROM
                                    ( 
                                    -- 1 - OBTENEMOS DETALLE DE MOVIMIENTOS 
                                    SELECT   --    INDEX(MF GPX_MOR_COM_NUMPER) INDEX(SG GPX_AA_SGRA_SGRAL)   INDEX(CL GPCNS_PK_LOTE_NUM_LOTE) 
                                            VIS.CVE_ENTIDAD       CVE_ENTIDAD
                                            ,VIS.FEC_PERIODO       FEC_PERIODO
                                            ,CL.FEC_PERIODO       FEC_PERIODO_LOTE
                                            ,VIS.CVE_MONEDA        CVE_MONEDA
                                            ,VIS.IMP_SALDO         IMP_SALDO
                                            ,VIS.CVE_TIPO_DEUDOR   CVE_TIPO_DEUDOR
                                            ,VIS.FEC_VENCIMIENTO   FEC_VENCIMIENTO   -- DATO DE IDENTIFICACION DEL ADEUDO 
                                            ,REF_CODIGO_MOROSO_ENT
                                            ,CVE_TIPO_VALOR
                                            ,FE.FEC_CONSULTA
                                            ,FE.FEC_CARGA_MORO
                                            ,VIS.NUM_LOTE_CARGA
                                            ,VIS.ES_ACTUAL
                                    FROM TABLE(GPPG_RC_DELTA.GET_DATOS_VISIBLES_MORO(p_NUM_PERSONA)) VIS
                                    INNER JOIN GPT_CARGA_LOTES CL   
                                            ON CL.NUM_LOTE_CARGA = VIS.NUM_LOTE_CARGA
                                    CROSS JOIN FECHAS_ENTIDADES FE
                                    WHERE VIS.ES_ACTUAL = 1 --SOLO ACTUALES PARA NEGATIVA
                                    -- 1 - OBTENEMOS DETALLE DE MOVIMIENTOS 
                                    )  
                                -- 2.- QUITAMOS REGISTROS DUPLICADOS 
                                )  DDMC
                            ON EFU.CVE_ENTIDAD = DDMC.CVE_ENTIDAD

                    -- DETALLE MOROSIDAD COMERCIAL 
                    ) vSG
        INNER JOIN (  --INICIO PR-276
                      SELECT  TO_NUMBER(CVE_MONEDA_ORIGEN) CVE_MONEDA_ORIGEN
                            , TO_NUMBER(CVE_MONEDA_DESTINO) CVE_MONEDA_DESTINO
                            ,MON_UNIDAD
                        FROM GPC_TIPO_CAMBIO GTC
                        INNER JOIN FECHAS_ENTIDADES FE
                                ON GTC.FEC_PERIODO = FE.FEC_TIPO_CAMBIO
                      WHERE   GTC.CVE_MONEDA_DESTINO = 10
                      UNION
                       SELECT 10 CVE_MONEDA_ORIGEN
                            , 10 CVE_MONEDA_DESTINO
                            , 1 MON_UNIDAD
                      FROM GPC_TIPO_CAMBIO
                      --FIN PR-276
                      )  TC
                ON TC.CVE_MONEDA_ORIGEN = vSG.CVE_MONEDA
        WHERE 1 = 1
        GROUP BY   'NEG'
            --  4- OBTENEMOS INFORMACION REQUERIDA 
    )
    CROSS JOIN FECHAS_ENTIDADES FE 
--  NEG- MOROSIDAD COMERCIAL  
)
/*NEGATIVA RCC*/
,LISTADO_CUENTAS_RCC AS
(

    SELECT 
            C.NUM_PERSONA
            ,C.NUM_SALDO 
            ,C.CVE_CUENTA 
            ,C.CVE_EMPRESA 
            ,CC.CVE_RUBRO 
            ,CC.CVE_TIPO 
            ,CC.CVE_MODALIDAD 
            ,CC.CVE_SUBMODALIDAD 
            ,CC.CVE_SITUACION 
            ,VIS.FEC_PERIODO
            ,VIS.CVE_CLASIFICACION CALIFICACION
            ,VIS.CAN_CON_DIAS
            ,VIS.IMP_MTO_SALDO
            ,C.CVE_MONEDA
    FROM GPT_CREDITO C
    INNER JOIN GPC_CUENTAS_CONTABLES CC 
            ON CC.CVE_CUENTA = C.CVE_CUENTA
    INNER JOIN TABLE(GPPG_RC_DELTA.GET_DATOS_VISIBLES_RCC(p_NUM_PERSONA)) VIS --TABLA CON REGLAS DE VISIBILIDAD APLICADAS
            ON VIS.NUM_SALDO = C.NUM_SALDO
            AND VIS.NUM_PERSONA = C.NUM_PERSONA
    CROSS JOIN   FECHAS_ENTIDADES FE
)
,CONSOLIDADO_CASTMOR_RCC AS 
(
    --  CASTIGOS RCC
    SELECT   3 CVE_TIPO_TARJETA
            ,MAX(CVE_TIPO_CREDITO) CVE_TIPO_CREDITO
            ,CVE_PRODUCTO
            ,MAX(FEC_PERIODO) FECHA_REPORTE_SBS
            ,MAX(CALIFICACION) CALIFICACION --SI ES REPORTADO EN CARGA ACTUAL SIGUE SIENDO MOROSO, EN CASO CONTRARIO ES CERRADO
            ,MAX(DES_CALIFICACION)  DES_CALIFICACION
            ,MAX(DES_TIPO_CREDITO) DES_TIPO_CREDITO
            ,MAX(DES_PRODUCTO) DES_PRODUCTO
            ,SUM(VENCIDO) VENCIDO 
            ,SUM(D_MOROSA) DEUDA_MOROSA --PR-272
    FROM (
           SELECT 
                    MAX(NUM_PERSONA) NUM_PERSONA
                    ,CVE_TIPO_CREDITO
                    ,CVE_PRODUCTO
                    ,FEC_PERIODO 
                    ,MAX(DECODE(FEC_PERIODO,FEC_CARGA_RCC,6,5)) CALIFICACION --SI ES REPORTADO EN CARGA ACTUAL SIGUE SIENDO MOROSO, EN CASO CONTRARIO ES CERRADO
                    ,MAX(DECODE(DECODE(FEC_PERIODO,FEC_CARGA_RCC,6,5),6,'ABIERTO','HISTÓRICO')) DES_CALIFICACION
                    ,MAX(DES_TIPO_CREDITO) DES_TIPO_CREDITO
                    ,MAX(DES_PRODUCTO) DES_PRODUCTO
                    ,SUM(VENCIDO) VENCIDO --NEGATIVA
                    ,0 D_MOROSA
            FROM 
                (
                SELECT 
                        RCC.NUM_PERSONA
                        ,'CAST' CVE_TIPO_CREDITO --C_PROD.CVE_TIPO_CREDITO
                        ,'RCC' DES_TIPO_CREDITO --C_PROD.DES_TIPO_CREDITO
                        ,'NEG' CVE_PRODUCTO --C_PROD.CVE_PRODUCTO
                        ,'Negativa' DES_PRODUCTO--C_PROD.DES_PRODUCTO
                        ,RCC.IMP_MTO_SALDO VENCIDO --NEGATIVA
                        ,RCC.FEC_PERIODO 
                        ,FE.FEC_CARGA_RCC
                    FROM LISTADO_CUENTAS_RCC RCC
                    INNER JOIN GPC_PRODUCTO_AGRUPAMIENTO C_PROD --+ FIRST_ROWS 
                            ON RCC.CVE_RUBRO=C_PROD.CVE_RUBRO
                            AND RCC.CVE_TIPO=DECODE(C_PROD.CVE_TIPO,NULL,RCC.CVE_TIPO,C_PROD.CVE_TIPO)
                            AND RCC.CVE_SITUACION=DECODE(C_PROD.CVE_SITUACION,NULL,RCC.CVE_SITUACION,C_PROD.CVE_SITUACION)
                            AND RCC.CVE_MODALIDAD=DECODE(C_PROD.CVE_MODALIDAD,NULL,RCC.CVE_MODALIDAD,C_PROD.CVE_MODALIDAD)
                            AND RCC.CVE_SUBMODALIDAD=DECODE(C_PROD.CVE_SUBMODALIDAD,NULL,RCC.CVE_SUBMODALIDAD,C_PROD.CVE_SUBMODALIDAD)
                    CROSS JOIN FECHAS_ENTIDADES FE
                    WHERE C_PROD.CVE_TIPO_AGRUPAMIENTO IN ('11')  --CASTIGOS 81-9-25
                        AND ((C_PROD.CVE_RUBRO = 81 AND C_PROD.CVE_SITUACION = '09' AND C_PROD.CVE_TIPO = '25')                    --Solo CASTICO RCC - PR-256
                            OR (C_PROD.CVE_RUBRO = 81 AND C_PROD.CVE_SITUACION = '03'))

                )
            WHERE FEC_PERIODO = FEC_CARGA_RCC--ULTIMO CASTIGO RCC 81-9-25
            GROUP BY 
                    CVE_TIPO_CREDITO
                    ,CVE_PRODUCTO
                    ,FEC_PERIODO            
            UNION
            SELECT --INICA PR-272
                    MAX(NUM_PERSONA) NUM_PERSONA
                    ,CVE_TIPO_CREDITO
                    ,CVE_PRODUCTO
                    ,FEC_PERIODO 
                    ,MAX(DECODE(FEC_PERIODO,FEC_CARGA_RCC,6,5)) CALIFICACION --SI ES REPORTADO EN CARGA ACTUAL SIGUE SIENDO MOROSO, EN CASO CONTRARIO ES CERRADO
                    ,MAX(DECODE(DECODE(FEC_PERIODO,FEC_CARGA_RCC,6,5),6,'ABIERTO','HISTÓRICO')) DES_CALIFICACION
                    ,MAX(DES_TIPO_CREDITO) DES_TIPO_CREDITO
                    ,MAX(DES_PRODUCTO) DES_PRODUCTO
                    ,0 VENCIDO
                    ,SUM(D_MOROSA) D_MOROSA --PR-272 DEUDA MOROSA SUMA DE LA 14-05 Y 14-06
            FROM    
                (
                SELECT 
                        RCC.NUM_PERSONA
                        ,'CAST' CVE_TIPO_CREDITO --C_PROD.CVE_TIPO_CREDITO
                        ,'RCC' DES_TIPO_CREDITO --C_PROD.DES_TIPO_CREDITO
                        ,'NEG' CVE_PRODUCTO --C_PROD.CVE_PRODUCTO
                        ,'Negativa' DES_PRODUCTO--C_PROD.DES_PRODUCTO
                        ,RCC.IMP_MTO_SALDO D_MOROSA
                        ,RCC.FEC_PERIODO 
                        ,FE.FEC_CARGA_RCC
                    FROM LISTADO_CUENTAS_RCC RCC
                    INNER JOIN GPC_PRODUCTO_AGRUPAMIENTO C_PROD --+ FIRST_ROWS 
                            ON RCC.CVE_RUBRO=C_PROD.CVE_RUBRO
                            AND RCC.CVE_TIPO=DECODE(C_PROD.CVE_TIPO,NULL,RCC.CVE_TIPO,C_PROD.CVE_TIPO)
                            AND RCC.CVE_SITUACION=DECODE(C_PROD.CVE_SITUACION,NULL,RCC.CVE_SITUACION,C_PROD.CVE_SITUACION)
                            AND RCC.CVE_MODALIDAD=DECODE(C_PROD.CVE_MODALIDAD,NULL,RCC.CVE_MODALIDAD,C_PROD.CVE_MODALIDAD)
                            AND RCC.CVE_SUBMODALIDAD=DECODE(C_PROD.CVE_SUBMODALIDAD,NULL,RCC.CVE_SUBMODALIDAD,C_PROD.CVE_SUBMODALIDAD)
                    CROSS JOIN FECHAS_ENTIDADES FE
                    WHERE C_PROD.CVE_TIPO_AGRUPAMIENTO IN ('09')  
                        AND C_PROD.CVE_TIPO_CREDITO = 'DD'                      
                        AND C_PROD.CVE_PRODUCTO IN('VEN','JUD') --DEUDA VENCIDA Y JUDICIAL DE RCC
                )
            WHERE FEC_PERIODO = FEC_CARGA_RCC --ULTIMO REGISTRO CARGADO CON RESPECTO A LA FECHA DE CARGA DE RCC
            GROUP BY CVE_TIPO_CREDITO
                    ,CVE_PRODUCTO
                    ,FEC_PERIODO       
                --FIN PR-272
        )
    WHERE VENCIDO + D_MOROSA > 0 --SOLO REGISTROS MAYORES A 0
    GROUP BY CVE_PRODUCTO  
)
, NEGATIVA_MICRO AS(
SELECT  --IMPLEMENTACIvìN DE LA HISTORIA PR-256 Y 272
        TIPO_TARJETA
        ,CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,FECHA_REPORTE
        ,TOT_DEUDA_DIRECTA --DEUDA CASTIGADA
        ,IDCALIFICACION
        ,DECODE(IDCALIFICACION,6,'ABIERTO',9,'HISTÓRICO') CALIFICACION
        ,VENCIDA_MENOR_30 --PR-372
        ,VENCIDA_MAYOR_30 --PR-372
        ,JUDICIAL
        ,DEUDA_MOROSA
        FROM 
            (
             SELECT  
                     3 TIPO_TARJETA
                    ,'NEG' CVE_PRODUCTO
                    ,'Negativa' DES_PRODUCTO
                    ,'CAST' CVE_TIPO_CREDITO
                    ,'Microfinanzas no supervisadas' DES_TIPO_CREDITO
                    ,MAX(MAXFECPERIODO) FECHA_REPORTE
                    ,SUM(D_CASTIGADA_MICRO) TOT_DEUDA_DIRECTA --PR-272 PONEMOS LA DUEDA TOTAL CASTIGADA EN EL CAMPO DE TOTAL DEUDA DIRECTA.
                    ,MAX(INFO_MICRO.CVE_CLASIFICACION)  IDCALIFICACION  
                    ,SUM(VENCIDA_MENOR_30) VENCIDA_MENOR_30 --PR-372
                    ,SUM(VENCIDA_MAYOR_30) VENCIDA_MAYOR_30 --PR-372
                    ,SUM(CJUDICIAL) JUDICIAL --COBRANZA JUDICIAL
                    ,SUM(VENCIDA_MENOR_30) + SUM(VENCIDA_MAYOR_30) + SUM(CJUDICIAL) DEUDA_MOROSA --DEUDA MOROSA SUMA DE MENOR Y MAYOR A 30 DIAS Y JUDICIAL
                FROM  
                    (
                    SELECT   
                            IDPRODUCTO
                            ,CVE_ENTIDAD
                            ,MAX(MAXFECPERIODO)  MAXFECPERIODO
                            ,SUM(D_MENOR30) VENCIDA_MENOR_30 --VENCIDA DIRECTA MENOR O IGUAL A 30 DIAS 
                            ,SUM(D_MAYOR30) VENCIDA_MAYOR_30 --VENCIDA DIRECTA MAYOR A 30 DIAS 
                            ,SUM(D_JUDICIAL) CJUDICIAL --DEUDA DIRECTA COBRANZA JUDICIAL
                            ,SUM(D_CASTIGADA_MICRO) D_CASTIGADA_MICRO --DEUDA CASTIGADA
                            ,MAX(FEC_CARGA_MICRO) FEC_CARGA_MICRO
                            ,MAX(CVE_CLASIFICACION) CVE_CLASIFICACION
                        FROM
                            (                                        
                            SELECT 
                                    'MNR' IDPRODUCTO
                                    ,INFO_BASE.CVE_ENTIDAD 
                                    ,INFO_BASE.MIN_FEC_PERIODO_ENTIDAD  MINFECPERIODO
                                    ,INFO_BASE.MAX_FEC_PERIODO_ENTIDAD  MAXFECPERIODO
                                    ,SUM(ROUND(INFO_BASE.D_MENOR30,2)) D_MENOR30 
                                    ,SUM(ROUND(INFO_BASE.D_MAYOR30,2)) D_MAYOR30 
                                    ,SUM(ROUND(INFO_BASE.D_JUDICIAL,2)) D_JUDICIAL 
                                    ,SUM(ROUND(INFO_BASE.D_CASTIGADA_MICRO,2)) D_CASTIGADA_MICRO 
                                    ,MAX(FEC_CARGA_MICRO) FEC_CARGA_MICRO
                                    ,MAX(CASE WHEN (ES_ACTUAL = 1) THEN 6 ELSE 9 END) CVE_CLASIFICACION --SOLO PARA VERIFICAR SI ES ABIERTO(6) O HIST”RICO(9)
                                FROM (
                                        SELECT  CVE_ENTIDAD
                                                ,FEC_PERIODO
                                                ,CVE_MONEDA
                                                ,MAX(MAX_FEC_PERIODO_ENTIDAD) MAX_FEC_PERIODO_ENTIDAD
                                                ,MIN(MIN_FEC_PERIODO_ENTIDAD) MIN_FEC_PERIODO_ENTIDAD
                                                ,MAX(FEC_PERIODO_LOTE) FEC_PERIODO_LOTE
                                                ,MAX(LAST_DAY_FEC_PERIODO) LAST_DAY_FEC_PERIODO
                                                ,MAX(FEC_CARGA_MICRO) FEC_CARGA_MICRO
                                                ,SUM(D_MENOR30) D_MENOR30
                                                ,SUM(D_MAYOR30) D_MAYOR30
                                                ,SUM(D_JUDICIAL) D_JUDICIAL
                                                ,SUM(D_CASTIGADA_MICRO) D_CASTIGADA_MICRO
                                                ,MAX(ES_ACTUAL) ES_ACTUAL
                                        FROM (
                                                SELECT  CVE_ENTIDAD
                                                    ,MAX_FEC_PERIODO_ENTIDAD
                                                    ,MIN_FEC_PERIODO_ENTIDAD
                                                    ,FEC_PERIODO
                                                    ,FEC_PERIODO_LOTE
                                                    ,IMP_SALDO
                                                    ,CVE_MONEDA
                                                    ,CVE_TIPO_SALDO
                                                    ,LAST_DAY_FEC_PERIODO
                                                    ,NUM_LOTE_CARGA
                                                    ,FEC_CARGA_MICRO
                                                    ,D_MENOR30
                                                    ,D_MAYOR30
                                                    ,D_JUDICIAL
                                                    ,D_CASTIGADA_MICRO
                                                    ,ES_ACTUAL
                                                    FROM (
                                                        SELECT  VIS.CVE_ENTIDAD
                                                                ,VIS.MAX_FEC_ENTIDAD MAX_FEC_PERIODO_ENTIDAD
                                                                ,VIS.MIN_FEC_ENTIDAD MIN_FEC_PERIODO_ENTIDAD
                                                                ,VIS.FEC_PERIODO
                                                                ,CL.FEC_PERIODO       FEC_PERIODO_LOTE                
                                                                ,CASE WHEN VIS.CVE_TIPO_SALDO IN (4,5,6,10)
                                                                    THEN VIS.IMP_SALDO
                                                                    ELSE
                                                                        0
                                                                END IMP_SALDO --SOLO CONSIDERAR LAS DEUDAS: MENOR Y MAYOR A 30 DIAS Y JUDICIAL
                                                                ,VIS.CVE_MONEDA
                                                                ,VIS.CVE_TIPO_SALDO
                                                                ,LAST_DAY(MAX(VIS.FEC_PERIODO) OVER (PARTITION BY VIS.CVE_ENTIDAD)) LAST_DAY_FEC_PERIODO --PR-372
                                                                ,VIS.NUM_LOTE_CARGA
                                                                ,FE.FEC_CARGA_MICRO
                                                                --INICIO PR-372
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,4,VIS.IMP_SALDO),0) D_MENOR30
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,5,VIS.IMP_SALDO),0) D_MAYOR30
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,6,VIS.IMP_SALDO),0) D_JUDICIAL
                                                                ,NVL(DECODE(VIS.CVE_TIPO_SALDO,10,VIS.IMP_SALDO),0) D_CASTIGADA_MICRO
                                                                ,VIS.ES_ACTUAL
                                                        FROM TABLE(GPPG_RC_DELTA.GET_DATOS_VISIBLES_MICRO(p_NUM_PERSONA)) VIS
                                                                INNER JOIN GPT_CARGA_LOTES CL
                                                                        ON VIS.NUM_LOTE_CARGA = CL.NUM_LOTE_CARGA
                                                                CROSS JOIN FECHAS_ENTIDADES FE
                                                        WHERE VIS.ES_ACTUAL = 1 --SOLO ACTUALES PARA NEGATIVA
                                                        )

                                            )
                                            GROUP BY FEC_PERIODO
                                                    ,CVE_ENTIDAD
                                                    ,CVE_MONEDA                                          
                                        ) INFO_BASE
                                 GROUP BY  INFO_BASE.CVE_ENTIDAD
                                          ,INFO_BASE.MIN_FEC_PERIODO_ENTIDAD 
                                          ,INFO_BASE.MAX_FEC_PERIODO_ENTIDAD 
                                          ,INFO_BASE.CVE_MONEDA
                                          ,INFO_BASE.FEC_PERIODO
                            )
                        GROUP BY  IDPRODUCTO,CVE_ENTIDAD
                    ) INFO_MICRO
                GROUP BY IDPRODUCTO
            )
)


-------------------------------------

      ,DETALLE_DEU AS (   
      
             /*  2 = SE OBTIENEN LOS ULTIMOS REGISTROS PARA UN PERIODO */
                            SELECT
                                 FEC_PERIODO
                                ,FEC_PERIODO_LOTE
                                ,IMP_SALDO
                                ,FEC_TRIBUTARIA
                                ,FEC_INI_COBRA
                                 /* LOS FECHAS MINIMAS DEBEN DETERMINARSE ANTES DE LOS FILTROS DE EXCLUSIvìN */ 
                                ,MIN(FEC_PERIODO) OVER (PARTITION BY 1 /* SOLO REFERENCIA */) MIN_FEC_PERIODO_ENTIDAD
                                ,MAX_FEC_PERIODO_ENTIDAD 
                                ,MAX_FECPE_LOT_MESENTIDAD
                                ,FEC_CARGA_SUNAT
                                ,FEC_CONSULTA
                                ,FEC_LASTDAYCONSULTA
                                ,FEC_PERIODO_GLOBAL_ENTIDAD
                                --ADICIONAL
                                ,CVE_ACREEDOR
                            FROM
                              (
                                 SELECT  
                                       FEC_PERIODO
                                      ,FEC_PERIODO_LOTE
                                      ,IMP_SALDO
                                      ,FEC_TRIBUTARIA
                                      ,FEC_INI_COBRA
                                      ,MAX_FECPE_LOT_MESENTIDAD
                                      /* LOS FECHAS MAXIMAS DEBEN DETERMINARSE ANTES DE LOS FILTROS DE EXCLUSIvìN */ 
                                      ,MAX(FEC_PERIODO) OVER (PARTITION BY FEC_TRIBUTARIA,CVE_DEPENDENCIA,CVE_ACREEDOR) MAX_FEC_REP_ADEUDO
                                      ,MIN(FEC_PERIODO) OVER (PARTITION BY FEC_TRIBUTARIA,CVE_DEPENDENCIA,CVE_ACREEDOR) MIN_FEC_REP_ADEUDO
                                      ,MAX(FEC_PERIODO) OVER (PARTITION BY 1 /* SOLO REFERENCIA */) MAX_FEC_PERIODO_ENTIDAD
                                      ,FEC_CARGA_SUNAT
                                      ,FEC_CONSULTA
                                      ,FEC_LASTDAYCONSULTA
                                      ,FEC_PERIODO_GLOBAL_ENTIDAD
                                      ,CVE_ACREEDOR
                                  FROM 
                                   (

                                        SELECT /*+ ORDERED INDEX(DEU GPX_DEUD_NUMPER) INDEX(SG GPX_AA_SDO_GEN_PER_IDX)   INDEX(CL GPCNS_PK_LOTE_NUM_LOTE) */
                                             SG.FEC_PERIODO      FEC_PERIODO
                                            ,CL.FEC_PERIODO       FEC_PERIODO_LOTE
                                            ,SG.IMP_SALDO         IMP_SALDO
                                            ,DEU.FEC_TRIBUTARIA   FEC_TRIBUTARIA
                                            ,DEU.CVE_ACREEDOR
                                            ,DEU.CVE_DEPENDENCIA
                                            ,DEU.FEC_INI_COBRA
                                            ,MAX(CL.FEC_PERIODO) OVER (PARTITION BY TO_CHAR(SG.FEC_PERIODO,'YYYYMM')) MAX_FECPE_LOT_MESENTIDAD 
                                            
                                            ,FE.FEC_CARGA_SUNAT
                                            ,FE.FEC_CONSULTA
                                            ,FE.FEC_LASTDAYCONSULTA
                                            ,FEC_PERIODO_GLOBAL_ENTIDAD
                                        FROM GPT_DEUDORES DEU, GPT_SALDOS_GENERALES SG
                                             ,GPT_CARGA_LOTES CL 
                                            ,FECHAS_ENTIDADES FE

                                        WHERE 
                                        CL.NUM_LOTE_CARGA = DEU.NUM_LOTE_CARGA
                                        AND   SG.IMP_SALDO  >= 1
                                        AND   SG.FEC_PERIODO  BETWEEN LAST_DAY(ADD_MONTHS(FE.FEC_CARGA_SUNAT,-60)) + 1  AND  FE.FEC_CARGA_SUNAT  /* 60 MESES DE CARGA */
                                        AND   SG.NUM_SALDO = DEU.NUM_SALDO
                                        AND   SG.NUM_PERSONA = DEU.NUM_PERSONA

                                        AND SG.NUM_PERSONA=p_NUM_PERSONA
                                    /* DETALLE DE INFORMACIvìN */
                                   )  
                               WHERE  FEC_PERIODO_LOTE  = MAX_FECPE_LOT_MESENTIDAD 
                               
                               
                             )     
                            WHERE 
                                 /* EXCLUIR LOS REGISTROS DE MAS DE 24 MESES */
                                 /* Y REGISTROS CON MAS DE 1825 DIAS A FECHA CONSULTA */
                                 /* Y REGISTROS CON FECHA EXTINCIvìN CON MAS DE 730 DIAS */
                                 MAX_FEC_REP_ADEUDO BETWEEN LAST_DAY(ADD_MONTHS(FEC_CARGA_SUNAT,-24)) + 1 AND  FEC_CARGA_SUNAT  /* 24 MESES DE CARGA */
                            AND  FEC_INI_COBRA >=  FEC_CONSULTA  - 1825      /* LOS 1825 DIAS*/
                       --     AND  MAX_FEC_REP_ADEUDO >=   FEC_CONSULTA  - 730             /* LA ULTIMA FECHA PERIODO SE CONSIDERA LA FECHA DE EXTINCIvìN DE LA OBLIGACIvìN */
      )
 
     ,SIGUIENTES_DEU AS
              (
                SELECT OM.CVE_ACREEDOR, NVL(MIN(SCL.FEC_PERIODO),TRUNC(SYSDATE))  FECHA_PAGO
                 FROM
                   (SELECT CVE_ACREEDOR, MAX(FEC_PERIODO_LOTE) FEC_PERIODO_LOTE
                      FROM DETALLE_DEU
                      GROUP BY  CVE_ACREEDOR
                   ) OM
                   , GPT_CARGA_LOTES SCL
                 WHERE SCL.FEC_CANCELACION (+)IS NULL
                 AND  SCL.CVE_ENTIDAD (+)= v_ENTIDAD_SUN
                 AND  SCL.CVE_TIPO_FUENTE (+)= v_FUENTE_DEU
                 AND  SCL.FEC_PERIODO  (+)>  OM.FEC_PERIODO_LOTE
                 GROUP BY OM.CVE_ACREEDOR
              )     
              
    , MOV_REPORTES_DEU AS
    (         
              SELECT
                 FEC_PERIODO
                ,FEC_PERIODO_LOTE
                ,IMP_SALDO
                ,FEC_TRIBUTARIA
                ,FEC_INI_COBRA
                 /* LOS FECHAS MINIMAS DEBEN DETERMINARSE ANTES DE LOS FILTROS DE EXCLUSIvìN */ 
                ,MIN(FEC_PERIODO) OVER (PARTITION BY 1 /* SOLO REFERENCIA */) MIN_FEC_PERIODO_ENTIDAD
                ,MAX_FEC_PERIODO_ENTIDAD 
                ,MAX_FECPE_LOT_MESENTIDAD
                ,FEC_CARGA_SUNAT
                ,FEC_CONSULTA
                ,FEC_LASTDAYCONSULTA
                ,FEC_PERIODO_GLOBAL_ENTIDAD       
               FROM DETALLE_DEU DET
                   JOIN SIGUIENTES_DEU SIG ON SIG.CVE_ACREEDOR=DET.CVE_ACREEDOR
                   WHERE SIG.FECHA_PAGO   >  FEC_CONSULTA  - 730  
      ) 


-------------------------------------
, NEGATIVA_SUNAT AS (




SELECT
        3 TIPO_TARJETA --3.- SUNAT, TARJETA CHICA EN EL FRONT
        ,'NEG' CVE_PRODUCTO
        ,'Negativa' DES_PRODUCTO
        ,'SUN' CVE_TIPO_CREDITO
        ,'Sunat Deudores' DES_TIPO_CREDITO
        ,MAXFECPERIODO FECHA_REPORTE
        ,IMP_MTO_SALDO TOT_DEUDA_DIRECTA
        ,CLASIFICACION IDCALIFICACION
        ,DECODE(CLASIFICACION,6,'ABIERTO','HISTÓRICO') CALIFICACION
FROM   
    (  
    
    
     SELECT  
           MIN(MIN_FEC_PERIODO_ENTIDAD)    MINFECPERIODO  
          ,MAX(MAX_FEC_PERIODO_ENTIDAD)    MAXFECPERIODO
          ,MAX(DECODE(CASE WHEN (LAST_DAY(FEC_PERIODO_GLOBAL_ENTIDAD) = FEC_CARGA_SUNAT) THEN 1 ELSE 0 END,0,5,6)) CLASIFICACION--PR-256
          ,SUM(DECODE(FEC_PERIODO,MAX_FEC_PERIODO_ENTIDAD,DECODE(MAX_FECPE_LOT_MESENTIDAD,FEC_PERIODO_GLOBAL_ENTIDAD,1,0),0))  NUMEROEMP  /* NUMERO DE REGISTROS EN LA ULTIMA CARGA */  
          ,MAX(DECODE(FEC_PERIODO,MAX_FEC_PERIODO_ENTIDAD,DECODE(MAX_FECPE_LOT_MESENTIDAD,FEC_PERIODO_GLOBAL_ENTIDAD,FEC_CONSULTA - FEC_INI_COBRA,NULL),NULL))  DIASATRASOACTUAL /* MAXIMO ATRASO EN LOS ULTIMOS 12 PERIODOS DE CARGA, SE TOMA A FECHA DEL PERIODO PORQUE LA INFORMACION SE ACTUALIZA VARIAS MESES AL MES*/
          ,MAX(CASE WHEN FEC_PERIODO >= LAST_DAY(ADD_MONTHS(MAX_FEC_PERIODO_ENTIDAD,-12)) + 1 THEN FEC_CONSULTA - FEC_INI_COBRA ELSE NULL END)  DIASATRASODOCE /* MAXIMO ATRASO EN LOS ULTIMOS 12 PERIODOS DE CARGA, SE TOMA A FECHA DEL PERIODO PORQUE LA INFORMACION SE ACTUALIZA VARIAS MESES AL MES*/
          ,SUM(DECODE(FEC_PERIODO,MAX_FEC_PERIODO_ENTIDAD,DECODE(MAX_FECPE_LOT_MESENTIDAD,FEC_PERIODO_GLOBAL_ENTIDAD,IMP_SALDO,0),0))  IMP_MTO_SALDO  /* NUMERO DE REGISTROS EN LA ULTIMA CARGA */  
          ,FEC_CARGA_SUNAT
    FROM   MOV_REPORTES_DEU
    GROUP BY FEC_CARGA_SUNAT)
)



  ,DETALLE_AFP AS
                   (
                              SELECT 
                                      D_AFP.FEC_PERIODO
                                      ,D_AFP.CVE_ENTIDAD
                                      ,D_AFP.CVE_TIPO_DEUDA
                                      ,D_AFP.FEC_ADEUDO
                                      ,D_AFP.CVE_COND_DEUDA
                                      ,D_AFP.FEC_PERIODO_LOTE
                                      ,NVL(SUM(DECODE(D_AFP.CVE_TIPO_SALDO,18, D_AFP.IMP_SALDO)),0) IMPORTE_DEUDA_AFP
                                      ,NVL(SUM(DECODE(D_AFP.CVE_TIPO_SALDO,17, D_AFP.IMP_SALDO)),0) IMPORTE_DEUDA_FONDO                                     
                              FROM
                                  (
                                         SELECT
                                               --LAST_DAY(SG.FEC_PERIODO)  FEC_PERIODO

                                               SG.FEC_PERIODO
                                              , CL.CVE_ENTIDAD
                                              ,AFP.CVE_TIPO_DEUDA
                                              ,LAST_DAY(AFP.FEC_ADEUDO) FEC_ADEUDO
                                              ,SG.IMP_SALDO
                                              ,SG.CVE_TIPO_SALDO /*17 DEUDA_FONDO 18 DEUDA_AFP*/
                                              ,CVE_COND_DEUDA
                                              ,CL.FEC_PERIODO FEC_PERIODO_LOTE
                                              ,MAX(CL.FEC_PERIODO) OVER (PARTITION BY CL.CVE_ENTIDAD, TO_CHAR(SG.FEC_PERIODO,'YYYYMM') ) MAX_FECPE_LOT_MESENTIDAD
                                              ,MAX(CL.FEC_PERIODO) OVER (PARTITION BY CL.CVE_ENTIDAD)  MAX_FECPE_LOT_ENTIDAD

                            --.             select SG.FEC_PERIODO, AFP.FEC_ADEUDO
                                          FROM GPT_AFP AFP
                                          INNER JOIN GPT_SALDOS_GENERALES SG
                                            ON SG.NUM_SALDO =   AFP.NUM_SALDO
                                            AND  SG.NUM_PERSONA = AFP.NUM_PERSONA
                                          INNER JOIN GPT_CARGA_LOTES CL
                                            ON CL.NUM_LOTE_CARGA=AFP.NUM_LOTE_CARGA
                                          INNER JOIN  GPC_ENTIDAD_FUENTE  EF
                                            ON EF.CVE_ENTIDAD = CL.CVE_ENTIDAD
                                          WHERE 
                                            EF.CVE_ESTATUS = 1     
                                          AND   SG.IMP_SALDO >= 1  /* VISIBILIDAD */
                                          AND  SG.FEC_PERIODO  BETWEEN  LAST_DAY(ADD_MONTHS(v_FEC_CARGA_AFP,-60)) + 1  AND v_FEC_CARGA_AFP
                                          AND  AFP.NUM_PERSONA = p_NUM_PERSONA   
                                      )    D_AFP

                         WHERE D_AFP.FEC_PERIODO_LOTE =     D_AFP.MAX_FECPE_LOT_MESENTIDAD
                           AND D_AFP.FEC_PERIODO_LOTE =     D_AFP.MAX_FECPE_LOT_ENTIDAD  

                           --APLICAMOS REGLA DE VISIBILIDAD -- 60 MESES
                           AND   FEC_ADEUDO >  LAST_DAY(v_FEC_CONSULTA)  - 1825                
                        group by 
                               D_AFP.FEC_PERIODO
                              ,D_AFP.CVE_ENTIDAD
                              ,D_AFP.CVE_TIPO_DEUDA
                              ,D_AFP.FEC_ADEUDO
                              ,D_AFP.CVE_COND_DEUDA
                              ,D_AFP.FEC_PERIODO_LOTE
               )    --DETALLE DE AFP ANTES DE VISIBILIDAD  24 MESES            

         , MOV_REPORTES AS 
            (

                      SELECT
                              MOV_REP.CVE_ENTIDAD
                              ,D_ENT.DES_ENTIDAD
                              ,MOV_REP.FEC_PERIODO 

                              ,MOV_REP.CVE_TIPO_DEUDA

                              ,D_TD.DES_TIPO_DEUDA
                              ,TO_CHAR(MOV_REP.FEC_ADEUDO,'Mon-YY', 'NLS_DATE_LANGUAGE = spanish') FEC_ADEUDO
                              ,MOV_REP.IMPORTE_DEUDA_AFP
                              ,MOV_REP.IMPORTE_DEUDA_FONDO
                              ,MOV_REP.CVE_COND_DEUDA

                              ,D_CD.DES_COND_DEUDA
                           --   ,MOV_REP.FEC_PERIODO_LOTE

                              ,DECODE(MOV_REP.FEC_PERIODO_LOTE, GENT.FEC_PERIODO_GLOBAL_ENTIDAD,6,5)  SITUACION 
                              ,DECODE(MOV_REP.FEC_PERIODO_LOTE, GENT.FEC_PERIODO_GLOBAL_ENTIDAD,1,0)  CARGA_ACT
                              ,MOV_REP.FEC_ADEUDO  FEC_ADEUDO_ORD
                              ,DECODE(MOV_REP.CVE_COND_DEUDA,'J',1,'A',2,3) ORDENAMIENTO_DEUDA
                      FROM     
                      (
                            SELECT  CL.CVE_ENTIDAD  
                             ,MAX(CL.FEC_PERIODO)  FEC_PERIODO_GLOBAL_ENTIDAD
                             FROM   GPT_CARGA_LOTES CL
                             WHERE  CL.FEC_CANCELACION IS NULL
                             AND    CVE_TIPO_FUENTE = (SELECT GPPG_RC.get_fuente('AFP') FROM DUAL)  --2 TIPO DE FUENTE MOROSIDAD
                             GROUP BY CL.CVE_ENTIDAD
                             ORDER BY CL.CVE_ENTIDAD                          
                      )  GENT
                        , DETALLE_AFP MOV_REP
                        , GPC_ENTIDAD_FUENTE  D_ENT
                        , GPC_COND_DEUDA      D_CD
                        , GPC_TIPO_DEUDA      D_TD
                        WHERE   1 = 1
                        AND D_ENT.CVE_ENTIDAD = MOV_REP.CVE_ENTIDAD
                        AND D_CD.CVE_COND_DEUDA = MOV_REP.CVE_COND_DEUDA
                        AND D_TD.CVE_TIPO_DEUDA = MOV_REP.CVE_TIPO_DEUDA
                        AND GENT.cve_ENTIDAD = MOV_REP.CVE_ENTIDAD
                        AND MOV_REP.FEC_PERIODO_LOTE = GENT.FEC_PERIODO_GLOBAL_ENTIDAD
             )
    ,CUENTAS_AGRUPADAS_AFP AS (
    SELECT     p_NUM_PERSONA NUM_PERSONA 
               ,MR.CVE_ENTIDAD
               ,MR.DES_ENTIDAD
               ,MR.FEC_PERIODO
               ,MR.CVE_TIPO_DEUDA
               ,MR.DES_TIPO_DEUDA
               ,MR.FEC_ADEUDO_ORD FEC_ADEUDO
               ,MR.IMPORTE_DEUDA_AFP
               ,MR.IMPORTE_DEUDA_FONDO
               ,MR.CVE_COND_DEUDA
               ,MR.DES_COND_DEUDA
               ,MR.SITUACION
               ,MR.ORDENAMIENTO_DEUDA
               ,MR.CARGA_ACT

        FROM  MOV_REPORTES MR
          )


    ,NEGATIVA_AFP AS(
                SELECT 
                        'NEG' CVE_PRODUCTO
                        ,'Negativa' DES_PRODUCTO
                        ,'AFP' CVE_TIPO_CREDITO
                        ,'AFP' DES_TIPO_CREDITO
                        ,COUNT(DISTINCT(CVE_ENTIDAD)) NUM_ENTIDADES
                        ,MAX(FEC_PERIODO) FEC_PERIODO
                        ,MAX(CVE_TIPO_DEUDA) CVE_TIPO_DEUDA
                        ,MAX(FEC_ADEUDO) FEC_ADEUDO
                        ,SUM(IMPORTE_DEUDA_AFP) IMPORTE_DEUDA_AFP
                        ,SUM(IMPORTE_DEUDA_FONDO) IMPORTE_DEUDA_FONDO
                        ,MAX(CVE_COND_DEUDA) CVE_COND_DEUDA
                        ,MAX(SITUACION) IDCALIFICACION
                        ,MAX(DECODE(SITUACION,5,'HISTÓRICO','ABIERTO')) CALIFICACION
                FROM CUENTAS_AGRUPADAS_AFP 
                WHERE  CVE_ENTIDAD IS NOT NULL  
                    OR (CVE_ENTIDAD IS NULL AND ROWNUM  = 1)
                GROUP BY NUM_PERSONA
    )
, CONSOLIDADO_NEGATIVA AS (

  SELECT 
        3 TIPO_TARJETA 
        ,CVE_PRODUCTO
        ,DES_PRODUCTO
        ,CVE_TIPO_CREDITO
        ,DES_TIPO_CREDITO
        ,MAXFECPERIODO FECHA_REPORTE
        ,DEUDADIRECTA TOT_DEUDA_DIRECTA --NEGATIVA
        ,CLASIFICACION IDCALIFICACION
        ,DECODE(CLASIFICACION,6,'ABIERTO','HISTÓRICO') CALIFICACION 
        ,0 MAX_MOROSIDAD_12 
        ,0 MAX_MOROSIDAD_ACTUAL
        ,0 ANTIGUEDAD   -- EXPRESADA EN MESES 
        ,0 NUM_ENTIDADES
        ,0 ENT_CON_ATRASO
        ,0 VIGENTE
        ,0 REESTRUCTURADO
        ,0 REFINANCIADO
        ,0 VENCIDO
        ,0 JUDICIAL
        ,0 INTERESES
        ,100.0 PCT_MOROSA
        ,0 PCT_MONEDA_EXTRANJERA
        ,0 DEUDA_INDIRECTA
        ,0 LINEA_CREDITO
        ,0 DEUDA_CORRIENTE 
        ,DEUDA_MOROSA --DEUDA MOROSA
FROM
       (
        SELECT
                CVE_PRODUCTO
                ,MAX(DES_PRODUCTO) DES_PRODUCTO
                ,CVE_TIPO_CREDITO
                ,MAX(DES_TIPO_CREDITO) DES_TIPO_CREDITO
                ,MAX(CLASIFICACION)  CLASIFICACION 
                ,SUM(DEUDADIRECTA) DEUDADIRECTA --NEGATIVA
                ,SUM(DEUDA_MOROSA) DEUDA_MOROSA
                ,MAX(MAXFECPERIODO) MAXFECPERIODO
        FROM(
                SELECT 
                        CVE_PRODUCTO
                        ,DES_PRODUCTO
                        ,CVE_TIPO_CREDITO
                        ,DES_TIPO_CREDITO
                        ,CLASIFICACION
                        ,DEUDADIRECTA --NEGATIVA
                        ,0 DEUDA_MOROSA
                        ,MAXFECPERIODO
                FROM PRE_CONSOLIDADO_MCOM
                WHERE CLASIFICACION = 6 --Solo los actuales
                UNION ALL 
                SELECT 
                        CVE_PRODUCTO
                        ,DES_PRODUCTO
                        ,CVE_TIPO_CREDITO
                        ,DES_TIPO_CREDITO  
                        ,CLASIFICACION
                        ,DEUDADIRECTA --NEGATIVA
                        ,0 DEUDA_MOROSA
                        ,MAXFECPERIODO
                FROM PRE_CONSOLIDADO_PROTESTOS
                WHERE CLASIFICACION = 6 --Solo los actuales
                UNION ALL
                SELECT 
                        CVE_PRODUCTO
                        ,DES_PRODUCTO
                        ,CVE_TIPO_CREDITO
                        ,DES_TIPO_CREDITO
                        ,CALIFICACION CLASIFICACION
                        ,VENCIDO DEUDADIRECTA --NEGATIVA (81-03 Y 81-25-09)
                        ,DEUDA_MOROSA --DEUDA MOROSA RCC (14-05 Y 14-06)
                        ,FECHA_REPORTE_SBS MAXFECPERIODO
                FROM CONSOLIDADO_CASTMOR_RCC
                WHERE CALIFICACION = 6 --Solo los actuales*/
                UNION ALL
                SELECT
                        CVE_PRODUCTO
                        ,DES_PRODUCTO
                        ,CVE_TIPO_CREDITO
                        ,DES_TIPO_CREDITO
                        ,IDCALIFICACION CLASIFICACION
                        ,TOT_DEUDA_DIRECTA DEUDADIRECTA --NEGATIVA (CASTIGOS; TIPO DE SALDO = 10)
                        ,DEUDA_MOROSA --DEUDA MOROSA SUMA DE MENOR Y MAYOR A 30 DIAS Y JUDICIAL
                        ,FECHA_REPORTE
                FROM NEGATIVA_MICRO
                WHERE IDCALIFICACION = 6 --Solo los actuales*/
                UNION ALL
                SELECT
                        CVE_PRODUCTO
                        ,DES_PRODUCTO
                        ,CVE_TIPO_CREDITO
                        ,DES_TIPO_CREDITO
                        ,IDCALIFICACION CLASIFICACION
                        ,TOT_DEUDA_DIRECTA DEUDADIRECTA --NEGATIVA
                        ,0 DEUDA_MOROSA --DEUDA MOROSA
                        ,FECHA_REPORTE MAXFECPERIODO 
                FROM NEGATIVA_SUNAT
                WHERE IDCALIFICACION = 6
                UNION ALL
                SELECT 
                        CVE_PRODUCTO
                        ,DES_PRODUCTO
                        ,CVE_TIPO_CREDITO
                        ,DES_TIPO_CREDITO
                        ,IDCALIFICACION CLASIFICACION
                        ,(IMPORTE_DEUDA_AFP + IMPORTE_DEUDA_FONDO) DEUDADIRECTA --NEGATIVA
                        ,0 DEUDA_MOROSA --DEUDA MOROSA 
                        ,FEC_PERIODO MAXFECPERIODO 
                FROM NEGATIVA_AFP
                WHERE IDCALIFICACION = 6
            )       
            GROUP BY CVE_PRODUCTO
                    ,CVE_TIPO_CREDITO
        )

    )  
    SELECT 
            TIPO_TARJETA
            ,CVE_PRODUCTO
            ,DES_PRODUCTO
            ,CVE_TIPO_CREDITO
            ,DES_TIPO_CREDITO
            ,FECHA_REPORTE
            ,TOT_DEUDA_DIRECTA
            ,IDCALIFICACION
            ,CALIFICACION
            ,MAX_MOROSIDAD_12
            ,MAX_MOROSIDAD_ACTUAL
            ,ANTIGUEDAD
            ,NUM_ENTIDADES
            ,ENT_CON_ATRASO
            ,VIGENTE
            ,REESTRUCTURADO
            ,REFINANCIADO
            ,VENCIDO
            ,JUDICIAL
            ,INTERESES
            ,PCT_MOROSA
            ,PCT_MONEDA_EXTRANJERA
            ,DEUDA_INDIRECTA
            ,LINEA_CREDITO
            ,DEUDA_CORRIENTE
            ,DEUDA_MOROSA
            ,p_NUM_PERSONA
            ,0 ES_INTERES
            ,v_numRegistro
    FROM CONSOLIDADO_NEGATIVA
    /******************************** FIN NEGATIVA -PR-256 *****************************/
    COMMIT; 
        /*****************INICIO VISTA RESUMEN CREDITO *****************************/
        OPEN SP_RESUMEN_DETALLE FOR --detalleProducto
        WITH TOTAL_DETALLE AS (
            SELECT 
                    CASE WHEN CVE_TIPO_CREDITO IN ('COR','BMD','SBR','ESP','IV','ESF') --TARJETA CON UN SOLO TITULO (PRODUCTO)
                        THEN 5
                    ELSE
                        CVE_TIPO_TARJETA
                    END CVE_TIPO_TARJETA
                    --CVE_TIPO_TARJETA
                    ,CVE_PRODUCTO
                    ,DES_PRODUCTO
                    ,DES_TIPO_CREDITO
                    ,IDCALIFICACION
                    ,FECHA_REPORTE
                    ,TOT_DEUDA_DIRECTA
                    ,CALIFICACION
                    ,MAX_MOROSIDAD_12
                    ,MAX_MOROSIDAD_ACTUAL
                    ,ANTIGUEDAD
                    ,NUM_ENTIDADES
                    ,ENT_CON_ATRASO
                    ,VIGENTE
                    ,REESTRUCTURADO
                    ,REFINANCIADO
                    ,VENCIDO
                    ,VENCIDA_MENOR_30 --PR-372
                    ,VENCIDA_MAYOR_30 --PR-372                    
                    ,JUDICIAL
                    ,PCT_MOROSA
                    ,PCT_MONEDA_EXTRANJERA
                    ,DEUDA_INDIRECTA
                    ,LINEA_CREDITO
                    ,DECODE(IDCALIFICACION,5,2,9,2,1) ORD_ACTUAL_HIST --PR-280
                    ,(CASE WHEN IDCALIFICACION IN (4,6)  /*PERDIDA*/
                                THEN 6
                            WHEN IDCALIFICACION IN (3)   /*DUDOSO*/
                                THEN 4
                            WHEN IDCALIFICACION IN (2)   /*DEFICIENTE*/
                                THEN 3
                            WHEN IDCALIFICACION IN (1)   /*PROBLEMAS POTENCIALES*/
                                THEN 2
                            WHEN IDCALIFICACION IN (0)   /*NORMAL*/
                                THEN 1 
                            WHEN IDCALIFICACION IN (9,5) /*CERRADA*/
                                THEN 5
                            ELSE 7
                        END)ORDENAMIENTO_CALIFICACION
                        --INICIO PR-280
                    ,(CASE  WHEN CVE_TIPO_CREDITO = 'CC'
                            THEN CASE WHEN CVE_PRODUCTO = 'TJ' /*Consumo-Tarjeta de crv©dito*/
                                            THEN 11
                                        WHEN CVE_PRODUCTO = 'PA' /*Consumo-Prv©stamo vehicular*/
                                            THEN 12
                                        WHEN CVE_PRODUCTO = 'OP' /*Consumo-Prv©stamos*/
                                            THEN 13
                                        WHEN CVE_PRODUCTO = 'PIG' /*Consumo-Pignoraticios*/
                                            THEN 14
                                        WHEN CVE_PRODUCTO = 'OCC' /*Consumo-Otros crv©ditos*/
                                            THEN 15
                                END 
                        WHEN CVE_TIPO_CREDITO = 'HIP'
                            THEN CASE   WHEN CVE_PRODUCTO = 'PR' /*Hipotecario-Prv©stamos*/
                                            THEN 21
                                        WHEN CVE_PRODUCTO = 'FMV' /*Hipotecario-Fondo MiVivienda*/
                                            THEN 22
                                        WHEN CVE_PRODUCTO = 'OCH' /*Hipotecario-Otros crv©ditos*/
                                            THEN 23
                                END
                        WHEN CVE_TIPO_CREDITO = 'MIC'
                            THEN CASE   WHEN CVE_PRODUCTO = 'TJ' /*Microempresa-Tarjeta de crv©dito*/
                                            THEN 31
                                        WHEN CVE_PRODUCTO = 'SOB' /*Microempresa-Sobregiros en cuenta*/
                                            THEN 32
                                        WHEN CVE_PRODUCTO = 'PR' /*Microempresa-Prv©stamos*/
                                            THEN 33
                                        WHEN CVE_PRODUCTO = 'AF' /*Microempresa-Arrendamiento financiero*/
                                            THEN 34
                                        WHEN CVE_PRODUCTO = 'OCM' /*Microempresa-Otros crv©ditos*/
                                            THEN 35
                                END
                        WHEN CVE_TIPO_CREDITO = 'PQE'
                            THEN CASE   WHEN CVE_PRODUCTO = 'TJ' /*Pequev±a empresa-Tarjeta de crv©dito*/
                                            THEN 41
                                        WHEN CVE_PRODUCTO = 'SOB' /*Pequev±a empresa-Sobregiros en cuenta*/
                                            THEN 42
                                        WHEN CVE_PRODUCTO = 'PR' /*Pequev±a empresa-Prv©stamos*/
                                            THEN 43
                                        WHEN CVE_PRODUCTO = 'AF' /*Pequev±a empresa-Arrendamiento financiero*/
                                            THEN 44
                                        WHEN CVE_PRODUCTO = 'OCP' /*Pequev±a empresa-Otros crv©ditos*/
                                            THEN 45
                                END
                        WHEN CVE_TIPO_CREDITO = 'MED'
                            THEN CASE   WHEN CVE_PRODUCTO = 'TJ' /*Mediana empresa-Tarjeta de crv©dito*/
                                            THEN 51
                                        WHEN CVE_PRODUCTO = 'SOB' /*Mediana empresa-Sobregiros en cuenta*/
                                            THEN 52
                                        WHEN CVE_PRODUCTO = 'DES' /*Mediana empresa-Descuentos*/
                                            THEN 53
                                        WHEN CVE_PRODUCTO = 'PR' /*Mediana empresa-Prv©stamos*/
                                            THEN 54
                                        WHEN CVE_PRODUCTO = 'AF' /*Mediana empresa-Arrendamiento financiero*/
                                            THEN 55
                                        WHEN CVE_PRODUCTO = 'OCM' /*Mediana empresa-Otros crv©ditos*/
                                            THEN 56
                                END
                        WHEN CVE_TIPO_CREDITO = 'GDE'
                            THEN CASE   WHEN CVE_PRODUCTO = 'TJ' /*Grande empresa-Tarjeta de crv©dito*/
                                            THEN 61
                                        WHEN CVE_PRODUCTO = 'DES' /*Grande empresa-Descuentos*/
                                            THEN 62
                                        WHEN CVE_PRODUCTO = 'PR' /*Grande empresa-Prv©stamos*/
                                            THEN 63
                                        WHEN CVE_PRODUCTO = 'AF' /*Grande empresa-Arrendamiento financiero*/
                                            THEN 64
                                        WHEN CVE_PRODUCTO = 'OCM' /*Grande empresa-Otros crv©ditos*/
                                            THEN 65
                                END
                        WHEN CVE_TIPO_CREDITO = 'COR' /*Corporativo*/
                            THEN 70
                        WHEN CVE_TIPO_CREDITO = 'BMD' /*Bancos multilaterales de desarrollo*/
                            THEN 80
                        WHEN CVE_TIPO_CREDITO = 'SBR' /*Soberanos*/
                            THEN 90
                        WHEN CVE_TIPO_CREDITO = 'ESP' /*Entidades del sector pv¿blico*/
                            THEN 100
                        WHEN CVE_TIPO_CREDITO = 'IV' /*Intermediarios de valores*/
                            THEN 110
                        WHEN CVE_TIPO_CREDITO = 'ESF' /*Empresas del sistema financiero*/
                            THEN 120
                        WHEN CVE_TIPO_CREDITO = 'MCF' /*Microfinanzas/Microempresas*/
                            THEN 130
                    ELSE
                            200
                    END)ORD_TIPOCREDITO_PRODUCTO --FIN PR-280
            FROM TMP_RESUMEN_CREDITO
            WHERE NUM_PERSONA=p_NUM_PERSONA AND CVE_PRODUCTO NOT IN ('GAR','CNT','LC')        /*NO MOSTRAR TARJETA DE GARANTIAS, CONTINGENTES, NI LC*/
                AND NUMERO_REGISTRO=v_numRegistro
                AND NOT(TOT_DEUDA_DIRECTA<=0 AND ES_INTERES>0) /*NO MOSTRAR CUENTAS DE SOLO INTERES*/
                AND NOT(CVE_TIPO_TARJETA = 3) --PR-250
                /*INICIA PR-281*/
                AND TOT_DEUDA_DIRECTA > 0 
                /*FIN PR-281*/
            --INICIO PR-280
          ORDER BY ORD_ACTUAL_HIST ASC
                        ,ORDENAMIENTO_CALIFICACION ASC
                        ,ORD_TIPOCREDITO_PRODUCTO ASC
                        ,TOT_DEUDA_DIRECTA DESC
        )
               SELECT   --XML_TOTAL_DEUDA_PRODUCTO
                        CVE_TIPO_TARJETA tipoTarjeta
                        ,DES_PRODUCTO labelProducto
                        ,DES_TIPO_CREDITO labelTipoProducto
                        ,IDCALIFICACION idCalificacion
                        ,TO_CHAR(FECHA_REPORTE,'YYYY-MM-DD') fechaReporteSBS
                        ,TOT_DEUDA_DIRECTA totDeudaDirecta
                        ,CALIFICACION calificacion
                        ,MAX_MOROSIDAD_12 maxMorosidad12meses
                        ,MAX_MOROSIDAD_ACTUAL maxMorosidadActual
                        ,ANTIGUEDAD antiguedad
                        ,NUM_ENTIDADES entReg
                        ,ENT_CON_ATRASO entAtrasos
                        ,VIGENTE deudaVigente
                        ,REESTRUCTURADO deudaReestructurada
                        ,REFINANCIADO deudaRefinanciada
                        ,VENCIDO deudaVencida
                        ,VENCIDA_MENOR_30 deudaVencidaMenor30
                        ,VENCIDA_MAYOR_30 deudaVencidaMayor30
                        ,JUDICIAL deudaJudicial
                        ,PCT_MOROSA pctDeudaMorosa
                        ,PCT_MONEDA_EXTRANJERA pctDeudaMonedaExt
                        ,DEUDA_INDIRECTA deudaIndirecta
                        ,LINEA_CREDITO lineaCredito --deudaProd
        FROM TOTAL_DETALLE
            /*INICIA PR-281*/
            WHERE TOT_DEUDA_DIRECTA > 0;
            /*FIN PR-281*/

        OPEN SP_RESUMEN_PRODUCTO FOR
        WITH TOTAL_DEUDA_TIPO_PRODUCTO AS 
        ( 
              SELECT 
                    CVE_TIPO_CREDITO
                ---INICIA PR-274
                    ,CASE  WHEN CVE_TIPO_CREDITO = 'CC' /*Consumo*/
                                THEN 1
                        WHEN CVE_TIPO_CREDITO = 'HIP' /*Hipotecario*/
                                THEN 2
                        WHEN CVE_TIPO_CREDITO = 'MIC' /*Microempresa*/
                                THEN 3
                        WHEN CVE_TIPO_CREDITO = 'PQE' /*Pequev±a empresa*/
                                THEN 4
                        WHEN CVE_TIPO_CREDITO = 'MED' /*Mediana empresa*/
                                THEN 5
                        WHEN CVE_TIPO_CREDITO = 'GDE' /*Grande empresa*/
                                THEN 6
                        WHEN CVE_TIPO_CREDITO = 'COR' /*Corporativo*/
                                THEN 7
                        WHEN CVE_TIPO_CREDITO = 'BMD' /*Bancos multilaterales de desarrollo*/
                                THEN 8
                        WHEN CVE_TIPO_CREDITO = 'SBR' /*Soberanos*/
                                THEN 9
                        WHEN CVE_TIPO_CREDITO = 'ESP' /*Entidades del sector publico*/
                                THEN 10
                        WHEN CVE_TIPO_CREDITO = 'IV' /*Intermediarios de valores*/
                                THEN 11
                        WHEN CVE_TIPO_CREDITO = 'ESF' /*Empresas del sistema financiero*/
                                THEN 12
                        ELSE 20
                        END ORD_TIPO_CREDITO
             ---   ---INICIA PR-274 
                    ,DES_TIPO_CREDITO
                    ,DEUDA_CORRIENTE -- O NEGATIVA_CASTIGOS PR-256
                    ,DEUDA_MOROSA -- O NEGATIVA_SUNAT PR-256
                    ,INTERESES -- O NEGATIVA_PROTESTOS PR-256
                    , NEGATIVA_AFP totDeudaAFP  --PR-256
                    , NEGATIVA_MOROSIDADCOM totDeudaMorosidades --PR-256
                    ,D_MOROSA_RCC_MICRO
                    ,TOTAL
                    ,TRUNC((DECODE(DEUDA_CORRIENTE,0,0,DEUDA_CORRIENTE/TOTAL))*100,2) PCTDEUDA_CORRIENTE
                    ,TRUNC((DECODE(DEUDA_MOROSA,0,0,DEUDA_MOROSA/TOTAL))*100,2) PCTDEUDA_MOROSA
                    ,TRUNC((DECODE(INTERESES,0,0,INTERESES/TOTAL))*100,2) PCTINTERESES
                    --INICIO PR-246, PR-256
                    ,DECODE(CVE_TIPO_CREDITO,'NEG',98,1) ORDEN_TOTALDEUDA   
                    --Si el datos es del consolidado de Negativa (NEG) cambiamos las etiquetas
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Castigos','Deuda al día') labelCorrienteCastigos 
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Deuda SUNAT','Deuda morosa') labelMorosaSunat
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Protestos no aclarados','Rendimientos devengados') labelInteresesProtestos
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Deuda AFP','') labelDeudaAFP
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Morosidades','') labelDeudaMorosidades
                    --FIN PR-246, PR-256
                FROM (
                    SELECT 
                         CVE_TIPO_CREDITO
                        ,DES_TIPO_CREDITO
                        , SUM(DECODE(IDCALIFICACION,9,0,5,0,DEUDA_CORRIENTE)) DEUDA_CORRIENTE
                        , SUM(DECODE(IDCALIFICACION,9,0,5,0,DEUDA_MOROSA)) DEUDA_MOROSA
                        , SUM(DECODE(IDCALIFICACION,9,0,5,0,INTERESES)) INTERESES
                        , 0 NEGATIVA_AFP --PR-256
                        , 0 NEGATIVA_MOROSIDADCOM --PR-256                        
                        , SUM (DECODE(IDCALIFICACION,9,0,5,0,DEUDA_CORRIENTE)+DECODE(IDCALIFICACION,9,0,5,0,DEUDA_MOROSA)+DECODE(IDCALIFICACION,9,0,5,0,INTERESES)) TOTAL
                        ,0 D_MOROSA_RCC_MICRO
                       FROM TMP_RESUMEN_CREDITO
                       WHERE NUM_PERSONA=p_NUM_PERSONA 
                            AND CVE_TIPO_CREDITO NOT IN ('OTR')
                            AND CVE_PRODUCTO NOT IN ('NEG') --PR-256
                            AND NUMERO_REGISTRO=v_numRegistro
                            AND CVE_PRODUCTO NOT IN ('LC')
                            AND CVE_TIPO_CREDITO NOT IN ('MOR')--PR-256
                    GROUP BY CVE_TIPO_CREDITO
                            ,DES_TIPO_CREDITO
                    --SE ELIMINO EL UNION ALL QUE TRAIA LA INFORMACIvìN DE GARANTIAS Y CONTINGENTES (CVE_TIPO_CREDITO = 'OTR') POR LA HISTORIA PR-246
                         UNION ALL
                     --Inicio PR-256
                    SELECT 
                         CVE_PRODUCTO CVE_TIPO_CREDITO --PR-256
                        ,DES_PRODUCTO DES_TIPO_CREDITO --PR-256
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'CAST',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) DEUDA_CORRIENTE--NEGATIVA_CASTIGOS 
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'SUN',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) DEUDA_MOROSA--NEGATIVA_SUNAT
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'PRO',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) INTERESES--NEGATIVA_PROTESTOS
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'AFP',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) NEGATIVA_AFP
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'MCOM',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) NEGATIVA_MOROSIDADCOM
                       ,SUM (DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA)) TOTAL
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'CAST',DECODE(IDCALIFICACION,9,0,5,0,DEUDA_MOROSA),0)) D_MOROSA_RCC_MICRO
                    FROM TMP_RESUMEN_CREDITO
                       WHERE NUM_PERSONA=p_NUM_PERSONA 
                            AND NUMERO_REGISTRO=v_numRegistro 
                            AND CVE_PRODUCTO  IN ('NEG') --PR-256
                    GROUP BY 
                      CVE_PRODUCTO 
                      ,DES_PRODUCTO
                    --Fin PR-256 
                            )
                ORDER BY ORDEN_TOTALDEUDA
                ---INICIA PR-274
                ,ORD_TIPO_CREDITO
                ---FIN PR-274
        )
        ,TOTAL_DEUDA_PERSONA AS 
        (

                SELECT 
                  CVE_ETIQUETA
                  , REF_DESCRIPCION_CORTA
                    ,DECODE (CVE_ETIQUETA,'GTOT', TOTAL
                                    ,'VTOT',DEUDA_CORRIENTE
                                    ,'MTOT',DEUDA_MOROSA
                                    ,'ITOT',INTERESES,0) total 
                    ,(TRUNC(DECODE (CVE_ETIQUETA,'GTOT', 1
                                     ,'VTOT',DECODE(DEUDA_CORRIENTE,0,0,(DEUDA_CORRIENTE/TOTAL))
                                     ,'MTOT',DECODE(DEUDA_MOROSA,0,0,(DEUDA_MOROSA/TOTAL))
                                     ,'ITOT',DECODE(INTERESES,0,0,(INTERESES/TOTAL))
                                     ,0),4)*100)  porcentaje


                   FROM
                    ( 
                        SELECT 
                            CVE_ETIQUETA
                            ,REF_DESCRIPCION_CORTA 
                            ,DECODE(CVE_ETIQUETA,'GTOT',1,'VTOT',2,'MTOT',3,4) OrdenEtiqueta
                        FROM GPC_ETIQUETAS_REPORTE
                        WHERE 
                            CVE_REPORTE=1
                            AND CVE_SECCION=1
                            AND CVE_ETIQUETA IN ( 'GTOT'
                                                 ,'VTOT'
                                                ,'MTOT'
                                                ,'ITOT') 
                    ) Etiq
                CROSS JOIN (
                SELECT SUM(DEUDA_CORRIENTE+DEUDA_MOROSA+INTERESES) TOTAL
                    ,DEUDA_CORRIENTE
                    ,DEUDA_MOROSA
                    ,INTERESES
                FROM (
                       SELECT
                            SUM(DECODE(CVE_TIPO_CREDITO,'OTR',0,'NEG',0,DEUDA_CORRIENTE)) DEUDA_CORRIENTE
                            --FIN PR-271
                            ,SUM(DECODE(CVE_TIPO_CREDITO,'OTR',0,'NEG',DEUDA_CORRIENTE --NEGATIVA CASTIGOS RCC-MICRO
                                                                        +DEUDA_MOROSA --NEGATIVA SUNAT
                                                                        +INTERESES --NEGATIVA PROTESTOS
                                                                        +totDeudaAFP --NEGATIVA AFP
                                                                        +totDeudaMorosidades --NEGATIVA MOROSIDAD
                                                                        +D_MOROSA_RCC_MICRO --DEUDA MOROSA DE RCC Y MICRO
                                                                        ,0)) DEUDA_MOROSA
                            --FIN PR-271
                            ,SUM(DECODE(CVE_TIPO_CREDITO,'OTR',0,'NEG',0,INTERESES)) INTERESES
                        FROM
                         TOTAL_DEUDA_TIPO_PRODUCTO) 
                    GROUP BY DEUDA_CORRIENTE
                            ,DEUDA_MOROSA
                            ,INTERESES) tProd

            ORDER BY OrdenEtiqueta

        )
        ,TOTAL_DEUDA_TIPO_FINAL AS(  
          SELECT 
                    CVE_TIPO_CREDITO
                    ,DES_TIPO_CREDITO
                    ,DEUDA_CORRIENTE
                    ,DEUDA_MOROSA
                    ,INTERESES
                    ,TOTAL
                    ,PCTDEUDA_CORRIENTE
                    ,PCTDEUDA_MOROSA
                    ,PCTINTERESES
                    ,ORDEN_TOTALDEUDA   
                    ,TRUNC( DECODE (totDeudaPersona,0,0,totDeudaProducto/totDeudaPersona)*100
                          ,2)  pctTotalTipoProducto
                    , labelCorrienteCastigos
                    , labelMorosaSunat                                         
                    , labelInteresesProtestos
                    , labelDeudaAFP
                    , labelDeudaMorosidades
                    , totDeudaAFP
                    , totDeudaMorosidades
                    FROM (

                             SELECT 
                                        CVE_TIPO_CREDITO
                                        ,DES_TIPO_CREDITO
                                        ,DEUDA_CORRIENTE
                                        ,DEUDA_MOROSA
                                        ,INTERESES
                                        ,TOTAL
                                        ,PCTDEUDA_CORRIENTE
                                        ,PCTDEUDA_MOROSA
                                        ,PCTINTERESES
                                        ,ORDEN_TOTALDEUDA   
                                        ,(DEUDA_CORRIENTE
                                                    +DECODE(CVE_TIPO_CREDITO,'OTR',0,DEUDA_MOROSA)
                                                    +DECODE (CVE_TIPO_CREDITO,'OTR',0,INTERESES)) totDeudaProducto
                                        ,(SELECT TOTAL FROM TOTAL_DEUDA_PERSONA  WHERE CVE_ETIQUETA='GTOT') totDeudaPersona
                                        , labelCorrienteCastigos
                                        , labelMorosaSunat
                                        , labelInteresesProtestos
                                        , labelDeudaAFP
                                        , labelDeudaMorosidades
                                        , totDeudaAFP
                                        , totDeudaMorosidades
                    FROM TOTAL_DEUDA_TIPO_PRODUCTO    )   
        )
            SELECT  --XML_TOTAL_DEUDA_TIPO_PRODUCTO,deudaTipoProducto
                   CVE_TIPO_CREDITO idTipoProducto
                   ,DES_TIPO_CREDITO labelTipoProducto
                   ,pctTotalTipoProducto pctTotalTipoProducto
                   ,DEUDA_CORRIENTE totDeudaCorrienteCastigos
                   ,DEUDA_MOROSA totDeudaMorosaSunat
                   ,INTERESES totInteresesProtestos
                   ,totDeudaAFP totDeudaAFP
                   ,totDeudaMorosidades totDeudaMorosidades
                   ,PCTDEUDA_CORRIENTE pctDeudaCorriente
                   ,PCTDEUDA_MOROSA pctDeudaMorosa
                   ,PCTINTERESES pctIntereses
                   ,labelCorrienteCastigos labelCorrienteCastigos
                   ,labelMorosaSunat labelMorosaSunat
                   ,labelInteresesProtestos labelInteresesProtestos
                   ,labelDeudaAFP labelDeudaAFP
                   ,labelDeudaMorosidades labelDeudaMorosidades
                    -- tipoProducto                                           
            FROM TOTAL_DEUDA_TIPO_FINAL
            /*INICIA PR-275  No se muestran las tarjetas que contengan cero.*/
            WHERE 
            DEUDA_CORRIENTE + DEUDA_MOROSA + INTERESES + totDeudaAFP + totDeudaMorosidades > 0;
            /*FIN PR-275*/
        OPEN SP_RESUMEN_PERSONA FOR
        WITH TOTAL_DEUDA_TIPO_PRODUCTO AS 
        ( 
              SELECT 
                    CVE_TIPO_CREDITO
                ---INICIA PR-274
                    ,CASE  WHEN CVE_TIPO_CREDITO = 'CC' /*Consumo*/
                                THEN 1
                        WHEN CVE_TIPO_CREDITO = 'HIP' /*Hipotecario*/
                                THEN 2
                        WHEN CVE_TIPO_CREDITO = 'MIC' /*Microempresa*/
                                THEN 3
                        WHEN CVE_TIPO_CREDITO = 'PQE' /*Pequev±a empresa*/
                                THEN 4
                        WHEN CVE_TIPO_CREDITO = 'MED' /*Mediana empresa*/
                                THEN 5
                        WHEN CVE_TIPO_CREDITO = 'GDE' /*Grande empresa*/
                                THEN 6
                        WHEN CVE_TIPO_CREDITO = 'COR' /*Corporativo*/
                                THEN 7
                        WHEN CVE_TIPO_CREDITO = 'BMD' /*Bancos multilaterales de desarrollo*/
                                THEN 8
                        WHEN CVE_TIPO_CREDITO = 'SBR' /*Soberanos*/
                                THEN 9
                        WHEN CVE_TIPO_CREDITO = 'ESP' /*Entidades del sector publico*/
                                THEN 10
                        WHEN CVE_TIPO_CREDITO = 'IV' /*Intermediarios de valores*/
                                THEN 11
                        WHEN CVE_TIPO_CREDITO = 'ESF' /*Empresas del sistema financiero*/
                                THEN 12
                        ELSE 20
                        END ORD_TIPO_CREDITO
             ---   ---INICIA PR-274 
                    ,DES_TIPO_CREDITO
                    ,DEUDA_CORRIENTE -- O NEGATIVA_CASTIGOS PR-256
                    ,DEUDA_MOROSA -- O NEGATIVA_SUNAT PR-256
                    ,INTERESES -- O NEGATIVA_PROTESTOS PR-256
                    , NEGATIVA_AFP totDeudaAFP  --PR-256
                    , NEGATIVA_MOROSIDADCOM totDeudaMorosidades --PR-256
                    ,D_MOROSA_RCC_MICRO
                    ,TOTAL
                    ,TRUNC((DECODE(DEUDA_CORRIENTE,0,0,DEUDA_CORRIENTE/TOTAL))*100,2) PCTDEUDA_CORRIENTE
                    ,TRUNC((DECODE(DEUDA_MOROSA,0,0,DEUDA_MOROSA/TOTAL))*100,2) PCTDEUDA_MOROSA
                    ,TRUNC((DECODE(INTERESES,0,0,INTERESES/TOTAL))*100,2) PCTINTERESES
                    --INICIO PR-246, PR-256
                    ,DECODE(CVE_TIPO_CREDITO,'NEG',98,1) ORDEN_TOTALDEUDA   
                    --Si el datos es del consolidado de Negativa (NEG) cambiamos las etiquetas
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Castigos','Deuda al día') labelCorrienteCastigos 
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Deuda SUNAT','Deuda morosa') labelMorosaSunat
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Protestos no aclarados','Rendimientos devengados') labelInteresesProtestos
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Deuda AFP','') labelDeudaAFP
                    ,DECODE(CVE_TIPO_CREDITO,'NEG','Morosidades','') labelDeudaMorosidades
                    --FIN PR-246, PR-256
                FROM (
                    SELECT 
                         CVE_TIPO_CREDITO
                        ,DES_TIPO_CREDITO
                        , SUM(DECODE(IDCALIFICACION,9,0,5,0,DEUDA_CORRIENTE)) DEUDA_CORRIENTE
                        , SUM(DECODE(IDCALIFICACION,9,0,5,0,DEUDA_MOROSA)) DEUDA_MOROSA
                        , SUM(DECODE(IDCALIFICACION,9,0,5,0,INTERESES)) INTERESES
                        , 0 NEGATIVA_AFP --PR-256
                        , 0 NEGATIVA_MOROSIDADCOM --PR-256                        
                        , SUM (DECODE(IDCALIFICACION,9,0,5,0,DEUDA_CORRIENTE)+DECODE(IDCALIFICACION,9,0,5,0,DEUDA_MOROSA)+DECODE(IDCALIFICACION,9,0,5,0,INTERESES)) TOTAL
                        ,0 D_MOROSA_RCC_MICRO
                       FROM TMP_RESUMEN_CREDITO
                       WHERE NUM_PERSONA=p_NUM_PERSONA 
                            AND CVE_TIPO_CREDITO NOT IN ('OTR')
                            AND CVE_PRODUCTO NOT IN ('NEG') --PR-256
                            AND NUMERO_REGISTRO=v_numRegistro
                            AND CVE_PRODUCTO NOT IN ('LC')
                            AND CVE_TIPO_CREDITO NOT IN ('MOR')--PR-256
                    GROUP BY CVE_TIPO_CREDITO
                            ,DES_TIPO_CREDITO
                    --SE ELIMINO EL UNION ALL QUE TRAIA LA INFORMACIvìN DE GARANTIAS Y CONTINGENTES (CVE_TIPO_CREDITO = 'OTR') POR LA HISTORIA PR-246
                         UNION ALL
                     --Inicio PR-256
                    SELECT 
                         CVE_PRODUCTO CVE_TIPO_CREDITO --PR-256
                        ,DES_PRODUCTO DES_TIPO_CREDITO --PR-256
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'CAST',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) DEUDA_CORRIENTE--NEGATIVA_CASTIGOS 
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'SUN',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) DEUDA_MOROSA--NEGATIVA_SUNAT
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'PRO',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) INTERESES--NEGATIVA_PROTESTOS
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'AFP',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) NEGATIVA_AFP
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'MCOM',DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA),0)) NEGATIVA_MOROSIDADCOM
                       ,SUM (DECODE(IDCALIFICACION,9,0,5,0,TOT_DEUDA_DIRECTA)) TOTAL
                       ,SUM(DECODE(CVE_TIPO_CREDITO,'CAST',DECODE(IDCALIFICACION,9,0,5,0,DEUDA_MOROSA),0)) D_MOROSA_RCC_MICRO
                    FROM TMP_RESUMEN_CREDITO
                       WHERE NUM_PERSONA=p_NUM_PERSONA 
                            AND NUMERO_REGISTRO=v_numRegistro 
                            AND CVE_PRODUCTO  IN ('NEG') --PR-256
                    GROUP BY 
                      CVE_PRODUCTO 
                      ,DES_PRODUCTO
                    --Fin PR-256 
                            )
                ORDER BY ORDEN_TOTALDEUDA
                ---INICIA PR-274
                ,ORD_TIPO_CREDITO
                ---FIN PR-274
        )
        ,TOTAL_DEUDA_PERSONA AS 
        (

                SELECT 
                  CVE_ETIQUETA
                  , REF_DESCRIPCION_CORTA
                    ,DECODE (CVE_ETIQUETA,'GTOT', TOTAL
                                    ,'VTOT',DEUDA_CORRIENTE
                                    ,'MTOT',DEUDA_MOROSA
                                    ,'ITOT',INTERESES,0) total 
                    ,(TRUNC(DECODE (CVE_ETIQUETA,'GTOT', 1
                                     ,'VTOT',DECODE(DEUDA_CORRIENTE,0,0,(DEUDA_CORRIENTE/TOTAL))
                                     ,'MTOT',DECODE(DEUDA_MOROSA,0,0,(DEUDA_MOROSA/TOTAL))
                                     ,'ITOT',DECODE(INTERESES,0,0,(INTERESES/TOTAL))
                                     ,0),4)*100)  porcentaje


                   FROM
                    ( 
                        SELECT 
                            CVE_ETIQUETA
                            ,REF_DESCRIPCION_CORTA 
                            ,DECODE(CVE_ETIQUETA,'GTOT',1,'VTOT',2,'MTOT',3,4) OrdenEtiqueta
                        FROM GPC_ETIQUETAS_REPORTE
                        WHERE 
                            CVE_REPORTE=1
                            AND CVE_SECCION=1
                            AND CVE_ETIQUETA IN ( 'GTOT'
                                                 ,'VTOT'
                                                ,'MTOT'
                                                ,'ITOT') 
                    ) Etiq
                CROSS JOIN (
                SELECT SUM(DEUDA_CORRIENTE+DEUDA_MOROSA+INTERESES) TOTAL
                    ,DEUDA_CORRIENTE
                    ,DEUDA_MOROSA
                    ,INTERESES
                FROM (
                       SELECT
                            SUM(DECODE(CVE_TIPO_CREDITO,'OTR',0,'NEG',0,DEUDA_CORRIENTE)) DEUDA_CORRIENTE
                            --FIN PR-271
                            ,SUM(DECODE(CVE_TIPO_CREDITO,'OTR',0,'NEG',DEUDA_CORRIENTE --NEGATIVA CASTIGOS RCC-MICRO
                                                                        +DEUDA_MOROSA --NEGATIVA SUNAT
                                                                        +INTERESES --NEGATIVA PROTESTOS
                                                                        +totDeudaAFP --NEGATIVA AFP
                                                                        +totDeudaMorosidades --NEGATIVA MOROSIDAD
                                                                        +D_MOROSA_RCC_MICRO --DEUDA MOROSA DE RCC Y MICRO
                                                                        ,0)) DEUDA_MOROSA
                            --FIN PR-271
                            ,SUM(DECODE(CVE_TIPO_CREDITO,'OTR',0,'NEG',0,INTERESES)) INTERESES
                        FROM
                         TOTAL_DEUDA_TIPO_PRODUCTO) 
                    GROUP BY DEUDA_CORRIENTE
                            ,DEUDA_MOROSA
                            ,INTERESES) tProd

            ORDER BY OrdenEtiqueta

        )
        SELECT  --XML_TOTAL_DEUDA_PERSONA,deudaPersona,totales
                REF_DESCRIPCION_CORTA labelTotal
                ,TOTAL total
                ,PORCENTAJE porcentaje
                --deudaPersona
        FROM TOTAL_DEUDA_PERSONA;

        /*****************FIN VISTA RESUMEN CREDITO *******************************/
  SELECT to_char(systimestamp,'hh24:mi:ss.FF') INTO v_FinProceso FROM DUAL;

  DELETE FROM TMP_RESUMEN_CREDITO WHERE NUM_PERSONA=p_NUM_PERSONA AND NUMERO_REGISTRO=v_numRegistro;
  COMMIT;
  dbms_output.put_line( 'Inicio'  ||  v_InicioProceso ||  ' Fin ' ||  v_FinProceso);

  EXCEPTION
  WHEN OTHERS THEN
    v_Mensaje_Error := SQLERRM;
    OPEN SP_RESUMEN_PERSONA FOR
          SELECT  --XML_TOTAL_DEUDA_PERSONA,deudaPersona,totales
                NULL labelTotal
                ,NULL total
                ,NULL porcentaje
                --deudaPersona
        FROM DUAL;
    OPEN SP_RESUMEN_PRODUCTO FOR
        SELECT  
                   NULL idTipoProducto
                   ,NULL labelTipoProducto
                   ,NULL pctTotalTipoProducto
                   ,NULL totDeudaCorrienteCastigos
                   ,NULL totDeudaMorosaSunat
                   ,NULL totInteresesProtestos
                   ,NULL totDeudaAFP
                   ,NULL totDeudaMorosidades
                   ,NULL pctDeudaCorriente
                   ,NULL pctDeudaMorosa
                   ,NULL pctIntereses
                   ,NULL labelCorrienteCastigos
                   ,NULL labelMorosaSunat
                   ,NULL labelInteresesProtestos
                   ,NULL labelDeudaAFP
                   ,NULL labelDeudaMorosidades
            FROM DUAL;
    OPEN SP_RESUMEN_DETALLE FOR
    SELECT   
            NULL tipoTarjeta
            ,NULL labelProducto
            ,NULL labelTipoProducto
            ,NULL idCalificacion
            ,NULL fechaReporteSBS
            ,NULL totDeudaDirecta
            ,NULL calificacion
            ,NULL maxMorosidad12meses
            ,NULL maxMorosidadActual
            ,NULL antiguedad
            ,NULL entReg
            ,NULL entAtrasos
            ,NULL deudaVigente
            ,NULL deudaReestructurada
            ,NULL deudaRefinanciada
            ,NULL deudaVencida
            ,NULL deudaVencidaMenor30
            ,NULL deudaVencidaMayor30
            ,NULL deudaJudicial
            ,NULL pctDeudaMorosa
            ,NULL pctDeudaMonedaExt
            ,NULL deudaIndirecta
            ,NULL lineaCredito --deudaProd
        FROM DUAL;
        
    dbms_output.put_line( 'error ' || v_Mensaje_Error  );

  END GPSP_OBTIENE_RESUMEN_CREDITO;