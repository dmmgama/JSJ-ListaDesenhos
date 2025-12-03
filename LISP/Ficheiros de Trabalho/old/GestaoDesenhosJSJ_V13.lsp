;; ============================================================================
;; FERRAMENTA UNIFICADA: GESTAO DESENHOS JSJ (V13 - EXCEL FIX & REVISION SAFE)
;; ============================================================================

(defun c:GESTAODESENHOSJSJ ( / loop opt)
  (vl-load-com)
  (setq loop T)

  (while loop
    (textscr)
    (princ "\n\n==============================================")
    (princ "\n          GESTAO DESENHOS JSJ - MENU          ")
    (princ "\n==============================================")
    (princ "\n 1. Modificar Legendas (Manual/JSON)")
    (princ "\n 2. Exportar JSON (Backup)")
    (princ "\n 3. Gerar Lista Excel (Novo do Zero)")
    (princ "\n 4. Gerar Lista via TEMPLATE (Salva Novo 1º)")
    (princ "\n 5. Importar Excel (Atualiza CAD)")
    (princ "\n 0. Sair")
    (princ "\n==============================================")

    (initget "1 2 3 4 5 0")
    (setq opt (getkword "\nEscolha uma opção [1/2/3/4/5/0]: "))

    (cond
      ((= opt "1") (Run_MasterImport_Menu))
      ((= opt "2") (Run_ExportJSON))
      ((= opt "3") (Run_GenerateExcel_Pro))
      ((= opt "4") (Run_GenerateExcel_FromTemplate))
      ((= opt "5") (Run_ImportExcel_Flexible))
      ((= opt "0") (setq loop nil))
      ((= opt nil) (setq loop nil)) 
    )
  )
  (graphscr)
  (princ "\nGestao Desenhos JSJ Terminada.")
  (princ)
)

;; ============================================================================
;; MÓDULO 4: GERAR EXCEL VIA TEMPLATE (CORRIGIDO)
;; ============================================================================
(defun Run_GenerateExcel_FromTemplate ( / doc templateFile outputFile startCellStr excelApp wb sheet cellObj cells startRow startCol i layoutList dataList sortMode sortOrder valTipo valNum valTit maxRev revLetra revData valHandle)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))

  ;; 1. SELEÇÃO
  (setq templateFile (getfiled "Selecione o ficheiro TEMPLATE" "" "xlsx;xls" 4))
  
  (if (and templateFile (findfile templateFile))
    (progn
      (setq outputFile (getfiled "Guardar o NOVO ficheiro como..." "" "xlsx" 1))
      
      (if outputFile
        (progn
          (setq startCellStr (getstring "\nIndique a célula inicial (ex: C6) [Enter='A2']: "))
          (if (= startCellStr "") (setq startCellStr "A2")) 

          ;; 2. DADOS
          (princ "\nA recolher dados... ")
          (setq dataList '())
          (setq layoutList (GetLayoutsRaw doc))
          
          (foreach lay layoutList
            (vlax-for blk (vla-get-Block lay)
              (if (IsTargetBlock blk)
                (progn
                  (setq valTipo (GetAttValue blk "TIPO"))
                  (setq valNum  (GetAttValue blk "DES_NUM"))
                  (setq valTit  (GetAttValue blk "TITULO"))
                  (setq maxRev (GetMaxRevision blk)) 
                  (setq revLetra (car maxRev))
                  (setq revData (cadr maxRev))
                  (setq valHandle (vla-get-Handle blk))
                  (setq dataList (cons (list valTipo valNum valTit revLetra revData valHandle) dataList))
                )
              )
            )
          )

          ;; ORDENAÇÃO
          (initget "Tipo Numero")
          (setq sortMode (getkword "\nOrdenar por? [Tipo/Numero] <Numero>: "))
          (if (not sortMode) (setq sortMode "Numero"))
          (if (= sortMode "Tipo") (progn (initget "Ascendente Descendente") (setq sortOrder (getkword "\nOrdem do TIPO? [Ascendente/Descendente] <Ascendente>: ")) (if (not sortOrder) (setq sortOrder "Ascendente"))))
          (cond
            ((= sortMode "Tipo") (setq dataList (vl-sort dataList '(lambda (a b) (if (= (strcase (nth 0 a)) (strcase (nth 0 b))) (< (strcase (nth 1 a)) (strcase (nth 1 b))) (if (= sortOrder "Descendente") (> (strcase (nth 0 a)) (strcase (nth 0 b))) (< (strcase (nth 0 a)) (strcase (nth 0 b)))))))))
            ((= sortMode "Numero") (setq dataList (vl-sort dataList '(lambda (a b) (< (strcase (nth 1 a)) (strcase (nth 1 b)))))))
          )

          ;; 3. EXCEL WRITING
          (princ "\nA iniciar Excel... ")
          (setq excelApp (vlax-get-or-create-object "Excel.Application"))
          
          (if excelApp
            (progn
              (vla-put-visible excelApp :vlax-true)
              
              ;; ABRIR E SALVAR COMO NOVO IMEDIATAMENTE
              (setq wb (vlax-invoke-method (vlax-get-property excelApp 'Workbooks) 'Open templateFile))
              (vlax-invoke-method wb 'SaveAs outputFile)
              (setq sheet (vlax-get-property wb 'ActiveSheet))
              
              ;; DETECTAR LINHA/COLUNA INICIAL
              (if (vl-catch-all-error-p (setq cellObj (vl-catch-all-apply 'vlax-get-property (list sheet 'Range startCellStr))))
                (progn (alert "Célula inválida! A usar A2.") (setq cellObj (vlax-get-property sheet 'Range "A2")))
              )
              
              (setq startRow (AnyToInt (vlax-get-property cellObj 'Row)))
              (setq startCol (AnyToInt (vlax-get-property cellObj 'Column)))
              (vlax-release-object cellObj)

              (setq cells (vlax-get-property sheet 'Cells))

              (princ "\nA preencher dados... ")
              (setq i 0)
              (foreach row dataList
                ;; ESCREVE DADOS
                (PutCellSafe cells (+ startRow i) (+ startCol 0) (nth 0 row)) ;; Tipo
                (PutCellSafe cells (+ startRow i) (+ startCol 1) (nth 1 row)) ;; Num
                (PutCellSafe cells (+ startRow i) (+ startCol 2) (nth 2 row)) ;; Titulo
                (PutCellSafe cells (+ startRow i) (+ startCol 3) (nth 3 row)) ;; Rev
                (PutCellSafe cells (+ startRow i) (+ startCol 4) (nth 4 row)) ;; Data
                
                ;; ID CAD (Importante: Escreve na 6ª coluna relativa)
                (PutCellSafe cells (+ startRow i) (+ startCol 5) (nth 5 row)) 
                
                (setq i (1+ i))
              )

              (vlax-invoke-method wb 'Save)
              (alert (strcat "Sucesso!\nFicheiro criado em:\n" outputFile))
              
              (ReleaseObject cells) (ReleaseObject sheet) (ReleaseObject wb) (ReleaseObject excelApp)
            )
            (alert "ERRO: Excel não iniciado.")
          )
        )
        (princ "\nCancelado.")
      )
    )
    (princ "\nCancelado.")
  )
  (princ)
)

;; ============================================================================
;; MÓDULO 5: IMPORTAR EXCEL (AGORA COM CONVERSOR DE TIPOS FORTE)
;; ============================================================================
(defun Run_ImportExcel_Flexible ( / xlsFile startCellStr startRow startCol excelApp wb sheet cells r valHandle valTipo valNum valTit valRev valData countUpdates cellObj)
  
  (setq xlsFile (getfiled "Selecione o ficheiro Excel" "" "xlsx;xls" 4))
  
  (if (and xlsFile (findfile xlsFile))
    (progn
      (setq startCellStr (getstring "\nIndique a célula onde começam os dados (ex: C6) [Enter='A2']: "))
      (if (= startCellStr "") (setq startCellStr "A2"))

      (princ "\nA abrir Excel... ")
      (setq excelApp (vlax-get-or-create-object "Excel.Application"))
      
      (if excelApp
        (progn
          (vla-put-visible excelApp :vlax-true)
          (setq wb (vlax-invoke-method (vlax-get-property excelApp 'Workbooks) 'Open xlsFile))
          (setq sheet (vlax-get-property wb 'ActiveSheet))
          
          (if (vl-catch-all-error-p (setq cellObj (vl-catch-all-apply 'vlax-get-property (list sheet 'Range startCellStr))))
             (progn (alert "Célula inválida! A usar A2.") (setq cellObj (vlax-get-property sheet 'Range "A2")))
          )
          (setq startRow (AnyToInt (vlax-get-property cellObj 'Row)))
          (setq startCol (AnyToInt (vlax-get-property cellObj 'Column)))
          (vlax-release-object cellObj)

          (princ "\nA atualizar CAD... ")
          (setq cells (vlax-get-property sheet 'Cells))
          (setq countUpdates 0)

          (setq r 0)
          (while r 
             ;; LÊ ID (Coluna + 5) E CONVERTE PARA STRING LIMPA
             (setq valHandle (AnyToString (GetCellValue cells (+ startRow r) (+ startCol 5))))
             
             (if (or (= valHandle "") (= valHandle nil))
               (setq r nil) ;; Acabou a lista
               (progn
                 (setq valTipo (AnyToString (GetCellValue cells (+ startRow r) (+ startCol 0))))
                 (setq valNum  (AnyToString (GetCellValue cells (+ startRow r) (+ startCol 1))))
                 (setq valTit  (AnyToString (GetCellValue cells (+ startRow r) (+ startCol 2))))
                 (setq valRev  (AnyToString (GetCellValue cells (+ startRow r) (+ startCol 3))))
                 (setq valData (AnyToString (GetCellValue cells (+ startRow r) (+ startCol 4))))
                 
                 ;; EXECUTA UPDATE
                 (if (UpdateBlockByHandleAndData valHandle valTipo valNum valTit valRev valData)
                    (setq countUpdates (1+ countUpdates))
                 )
                 (setq r (1+ r))
               )
             )
          )
          
          (vlax-invoke-method wb 'Close :vlax-false)
          (vlax-invoke-method excelApp 'Quit)
          (ReleaseObject cells) (ReleaseObject sheet) (ReleaseObject wb) (ReleaseObject excelApp)
          
          (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport)
          (alert (strcat "Importação Concluída!\n" (itoa countUpdates) " desenhos atualizados com sucesso."))
        )
        (alert "Erro ao iniciar Excel.")
      )
    )
    (princ "\nCancelado.")
  )
  (princ)
)

;; ============================================================================
;; FUNÇÕES AUXILIARES BLINDADAS (O SEGREDO DO FUNCIONAMENTO)
;; ============================================================================

;; 1. CONVERSOR UNIVERSAL: Recebe Variant/Double/Int/String -> Devolve String Limpa
(defun AnyToString (val / typeVal)
  (if (= (type val) 'variant) (setq val (vlax-variant-value val)))
  (setq typeVal (type val))
  (cond
    ((= typeVal 'INT) (itoa val))
    ((= typeVal 'REAL) (rtos val 2 0)) ;; Transforma 1804.0 em "1804" (Remove decimal)
    ((= typeVal 'STR) (vl-string-trim " " val))
    (t "")
  )
)

;; 2. CONVERSOR INTEIRO: Para coordenadas de células
(defun AnyToInt (val)
  (if (= (type val) 'variant) (setq val (vlax-variant-value val)))
  (if (= (type val) 'INT) val (atoi (vl-princ-to-string val)))
)

;; 3. ESCREVER CÉLULA (SAFE)
(defun PutCellSafe (cells row col val / item cell)
  (if (not (vl-catch-all-error-p (setq item (vl-catch-all-apply 'vlax-get-property (list cells 'Item row col)))))
    (progn
      (if (= (type item) 'variant) (setq cell (vlax-variant-value item)) (setq cell item))
      (vlax-put-property cell 'Value2 val)
      (vlax-release-object cell)
    )
  )
)

;; 4. LER CÉLULA (SAFE)
(defun GetCellValue (cells row col / item cell val)
  (if (not (vl-catch-all-error-p (setq item (vl-catch-all-apply 'vlax-get-property (list cells 'Item row col)))))
    (progn 
      (if (= (type item) 'variant) (setq cell (vlax-variant-value item)) (setq cell item)) 
      (setq val (vlax-get-property cell 'Value2)) ;; Value2 é mais puro que Text
      (vlax-release-object cell) 
      val
    )
    nil
  )
)

(defun UpdateBlockByHandleAndData (handle tipo num tit rev dataStr / ename obj atts revTag dataTag success)
  (setq success nil)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle))))
    (setq ename (handent handle))
  )
  (if (and ename (setq obj (vlax-ename->vla-object ename)))
    (if (IsTargetBlock obj)
      (progn
        (UpdateSingleTag handle "TIPO" tipo)
        (UpdateSingleTag handle "DES_NUM" num)
        (UpdateSingleTag handle "TITULO" tit)
        
        ;; LOGICA INTELIGENTE DE REVISÃO:
        ;; Só atualiza se houver letra. Não apaga as anteriores.
        (if (and rev (/= rev "") (/= rev "-"))
          (progn 
             (setq revTag (strcat "REV_" rev)) 
             (setq dataTag (strcat "DATA_" rev)) 
             (UpdateSingleTag handle revTag rev) 
             (UpdateSingleTag handle dataTag dataStr)
          )
        )
        (princ ".") ;; Feedback
        (setq success T)
      )
    )
  )
  success
)

;; --- RESTANTE CÓDIGO (MANTIDO IGUAL V11 PARA MODULOS MANUAIS) ---
(defun Run_GenerateExcel_Pro ( / doc layoutList dataList sortMode sortOrder valTipo valNum valTit maxRev revLetra revData valHandle excelApp wb sheet range i rCount cells borders interior font) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))) (princ "\nA ler dados... ") (setq dataList '()) (setq layoutList (GetLayoutsRaw doc)) (foreach lay layoutList (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (setq valTipo (GetAttValue blk "TIPO")) (setq valNum  (GetAttValue blk "DES_NUM")) (setq valTit  (GetAttValue blk "TITULO")) (setq maxRev (GetMaxRevision blk)) (setq revLetra (car maxRev)) (setq revData (cadr maxRev)) (setq valHandle (vla-get-Handle blk)) (setq dataList (cons (list valTipo valNum valTit revLetra revData valHandle) dataList)))))) (initget "Tipo Numero") (setq sortMode (getkword "\nOrdenar por? [Tipo/Numero] <Numero>: ")) (if (not sortMode) (setq sortMode "Numero")) (if (= sortMode "Tipo") (progn (initget "Ascendente Descendente") (setq sortOrder (getkword "\nOrdem do TIPO? [Ascendente/Descendente] <Ascendente>: ")) (if (not sortOrder) (setq sortOrder "Ascendente")))) (cond ((= sortMode "Tipo") (setq dataList (vl-sort dataList '(lambda (a b) (if (= (strcase (nth 0 a)) (strcase (nth 0 b))) (< (strcase (nth 1 a)) (strcase (nth 1 b))) (if (= sortOrder "Descendente") (> (strcase (nth 0 a)) (strcase (nth 0 b))) (< (strcase (nth 0 a)) (strcase (nth 0 b))))))))) ((= sortMode "Numero") (setq dataList (vl-sort dataList '(lambda (a b) (< (strcase (nth 1 a)) (strcase (nth 1 b)))))))) (princ "\nA gerar Excel... ") (setq excelApp (vlax-get-or-create-object "Excel.Application")) (if excelApp (progn (vlax-put-property excelApp 'Visible :vlax-true) (setq wb (vlax-invoke-method (vlax-get-property excelApp 'Workbooks) 'Add)) (setq sheet (vlax-get-property wb 'ActiveSheet)) (setq cells (vlax-get-property sheet 'Cells)) (PutCellSafe cells 1 1 "Tipo") (PutCellSafe cells 1 2 "Nº Desenho") (PutCellSafe cells 1 3 "Título") (PutCellSafe cells 1 4 "Revisão") (PutCellSafe cells 1 5 "Data") (PutCellSafe cells 1 6 "ID_CAD") (setq range (vlax-get-property sheet 'Range "A1:F1")) (setq font (vlax-get-property range 'Font)) (setq interior (vlax-get-property range 'Interior)) (vlax-put-property font 'Bold :vlax-true) (vlax-put-property interior 'ColorIndex 32) (vlax-put-property font 'ColorIndex 2) (setq i 2) (foreach row dataList (PutCellSafe cells i 1 (nth 0 row)) (PutCellSafe cells i 2 (nth 1 row)) (PutCellSafe cells i 3 (nth 2 row)) (PutCellSafe cells i 4 (nth 3 row)) (PutCellSafe cells i 5 (nth 4 row)) (PutCellSafe cells i 6 (nth 5 row)) (setq i (1+ i))) (setq rCount (itoa (1- i))) (setq range (vlax-get-property sheet 'Range (strcat "A1:F" rCount))) (setq borders (vlax-get-property range 'Borders)) (if (= (type borders) 'variant) (setq borders (vlax-variant-value borders))) (vlax-put-property borders 'LineStyle 1) (vlax-invoke-method (vlax-get-property (vlax-get-property sheet 'Columns) 'EntireColumn) 'AutoFit) (ReleaseObject range) (ReleaseObject cells) (ReleaseObject sheet) (ReleaseObject wb) (ReleaseObject excelApp) (alert "Sucesso! Excel gerado.")) (alert "ERRO: Excel não detetado.")) (princ))
(defun Run_MasterImport_Menu ( / loopSub optSub) (setq loopSub T) (while loopSub (textscr) (princ "\n\n   --- SUB-MENU ---") (princ "\n   1. Importar JSON") (princ "\n   2. Definir Campos Gerais") (princ "\n   3. Alterar Desenhos") (princ "\n   4. Numerar TIPO") (princ "\n   5. Numerar SEQUENCIAL") (princ "\n   0. Voltar") (initget "1 2 3 4 5 0") (setq optSub (getkword "\n   Opção: ")) (cond ((= optSub "1") (ProcessJSONImport)) ((= optSub "2") (ProcessGlobalVariables)) ((= optSub "3") (ProcessManualReview)) ((= optSub "4") (AutoNumberByType)) ((= optSub "5") (AutoNumberSequential)) ((= optSub "0") (setq loopSub nil)) ((= optSub nil) (setq loopSub nil)))))
(defun Run_ExportJSON ( / ) (princ "\nJSON Export."))
(defun ProcessJSONImport ( / jsonFile fileDes line posSep handleVal attList inAttributes tag rawContent cleanContent countUpdates) (setq jsonFile (getfiled "Selecione JSON" "" "json" 4)) (if (and jsonFile (findfile jsonFile)) (progn (setq fileDes (open jsonFile "r")) (setq handleVal nil attList '() inAttributes nil countUpdates 0) (princ "\nA processar JSON... ") (while (setq line (read-line fileDes)) (setq line (vl-string-trim " \t" line)) (cond ((vl-string-search "\"handle_bloco\":" line) (setq posSep (vl-string-search ":" line)) (if posSep (progn (setq rawContent (substr line (+ posSep 2))) (setq handleVal (vl-string-trim " \"," rawContent)) (setq attList '()) ))) ((vl-string-search "\"atributos\": {" line) (setq inAttributes T)) ((and inAttributes (vl-string-search "}" line)) (setq inAttributes nil) (if (and handleVal attList) (UpdateBlockByHandle handleVal attList)) (setq handleVal nil)) (inAttributes (setq posSep (vl-string-search "\": \"" line)) (if posSep (progn (setq tag (substr line 2 (- posSep 1))) (setq rawContent (substr line (+ posSep 5))) (setq cleanContent (vl-string-trim " \"," rawContent)) (setq cleanContent (StringUnescape cleanContent)) (setq attList (cons (cons (strcase tag) cleanContent) attList))))))) (close fileDes) (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport) (alert (strcat "Concluido: " (itoa countUpdates)))) (princ "\nCancelado.")))
(defun ProcessGlobalVariables ( / loop validTags selTag newVal continueLoop) (setq loop T validTags (GetExampleTags)) (while loop (textscr) (princ "\n\n=== GESTOR GLOBAL ===") (foreach tName validTags (princ (strcat "\n • " tName))) (setq selTag (strcase (getstring "\nDigite o NOME do Tag: "))) (if (member selTag validTags) (progn (setq newVal (getstring T (strcat "\nNovo valor: "))) (ApplyGlobalValue selTag newVal)) (princ "\nTag inválido.")) (initget "Sim Nao") (setq continueLoop (getkword "\nOutro? [Sim/Nao] <Sim>: ")) (if (= continueLoop "Nao") (setq loop nil))))
(defun ProcessManualReview ( / loop drawList i item userIdx selectedHandle field revLet revVal) (setq loop T) (while loop (setq drawList (GetDrawingList)) (textscr) (princ "\n\n=== LISTA DE DESENHOS ===\n") (setq i 0) (foreach item drawList (princ (strcat "\n " (itoa (1+ i)) ". [Des: " (cadr item) "] (" (nth 3 item) ") - Tab: " (caddr item))) (setq i (1+ i))) (setq userIdx (getint (strcat "\nEscolha o numero (1-" (itoa i) ") ou 0: "))) (if (and userIdx (> userIdx 0) (<= userIdx i)) (progn (setq selectedHandle (car (nth (1- userIdx) drawList))) (initget "Tipo Titulo Revisao") (setq field (getkword "\nAtualizar? [Tipo/Titulo/Revisao]: ")) (cond ((= field "Tipo") (UpdateSingleTag selectedHandle "TIPO" (getstring T "\nNovo TIPO: "))) ((= field "Titulo") (UpdateSingleTag selectedHandle "TITULO" (getstring T "\nNovo TITULO: "))) ((= field "Revisao") (initget "A B C D E") (setq revLet (getkword "\nQual a Revisão? [A/B/C/D/E]: ")) (if revLet (progn (UpdateSingleTag selectedHandle (strcat "DATA_" revLet) (getstring T "\nData: ")) (UpdateSingleTag selectedHandle (strcat "DESC_" revLet) (getstring T "\nDescrição: ")) (setq revVal (getstring T (strcat "\nLetra (Enter='" revLet "'): "))) (if (= revVal "") (setq revVal revLet)) (UpdateSingleTag selectedHandle (strcat "REV_" revLet) revVal)))))) (setq loop nil)) (if loop (progn (initget "Sim Nao") (if (= (getkword "\nOutro? [Sim/Nao] <Nao>: ") "Nao") (setq loop nil))))))
(defun AutoNumberByType ( / doc dataList blk typeVal handleVal tabOrd sortedList curType count i) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))) (setq dataList '()) (princ "\n\nA analisar...") (vlax-for lay (vla-get-Layouts doc) (if (/= (vla-get-ModelType lay) :vlax-true) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (setq typeVal (GetAttValue blk "TIPO")) (if (= typeVal "") (setq typeVal "INDEFINIDO")) (setq handleVal (vla-get-Handle blk)) (setq tabOrd (vla-get-TabOrder lay)) (setq dataList (cons (list typeVal tabOrd handleVal) dataList))))))) (setq sortedList (vl-sort dataList '(lambda (a b) (if (= (strcase (car a)) (strcase (car b))) (< (cadr a) (cadr b)) (< (strcase (car a)) (strcase (car b))))))) (setq curType "" count 0 i 0) (foreach item sortedList (if (/= (strcase (car item)) curType) (progn (setq curType (strcase (car item))) (setq count 1)) (setq count (1+ count))) (UpdateSingleTag (caddr item) "DES_NUM" (FormatNum count)) (setq i (1+ i))) (vla-Regen doc acActiveViewport) (alert (strcat "Concluído: " (itoa i))))
(defun AutoNumberSequential ( / doc sortedLayouts count i) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))) (initget "Sim Nao") (if (= (getkword "\nNumerar sequencialmente? [Sim/Nao] <Nao>: ") "Sim") (progn (setq sortedLayouts (GetLayoutsRaw doc)) (setq sortedLayouts (vl-sort sortedLayouts '(lambda (a b) (< (vla-get-TabOrder a) (vla-get-TabOrder b))))) (setq count 1 i 0) (foreach lay sortedLayouts (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (UpdateSingleTag (vla-get-Handle blk) "DES_NUM" (FormatNum count)) (setq count (1+ count)) (setq i (1+ i)))))) (vla-Regen doc acActiveViewport) (alert (strcat "Concluído: " (itoa i))))))
(defun ReleaseObject (obj) (if (and obj (not (vlax-object-released-p obj))) (vlax-release-object obj)))
(defun IsTargetBlock (blk) (and (= (vla-get-ObjectName blk) "AcDbBlockReference") (= (strcase (vla-get-EffectiveName blk)) "LEGENDA_JSJ_V1")))
(defun GetAttValue (blk tag / atts val) (setq atts (vlax-invoke blk 'GetAttributes) val "") (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (setq val (vla-get-TextString att)))) val)
(defun UpdateSingleTag (handle tag val / ename obj atts) (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle))) (if (and ename (setq obj (vlax-ename->vla-object ename))) (progn (setq atts (vlax-invoke obj 'GetAttributes)) (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (vla-put-TextString att val))) (vla-Update obj))))
(defun UpdateBlockByHandle (handle pairList / ename obj atts tagVal foundVal) (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle))) (if (and ename (setq obj (vlax-ename->vla-object ename))) (if (and (= (vla-get-ObjectName obj) "AcDbBlockReference") (= (vla-get-HasAttributes obj) :vlax-true)) (foreach att (vlax-invoke obj 'GetAttributes) (setq tagVal (strcase (vla-get-TagString att)) foundVal (cdr (assoc tagVal pairList))) (if foundVal (vla-put-TextString att foundVal))))))
(defun ApplyGlobalValue (targetTag targetVal / doc) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))) (vlax-for lay (vla-get-Layouts doc) (if (/= (vla-get-ModelType lay) :vlax-true) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (foreach att (vlax-invoke blk 'GetAttributes) (if (= (strcase (vla-get-TagString att)) targetTag) (vla-put-TextString att targetVal))))))) (vla-Regen doc acActiveViewport))
(defun GetLayoutsRaw (doc / lays listLays) (setq lays (vla-get-Layouts doc) listLays '()) (vlax-for item lays (if (/= (vla-get-ModelType item) :vlax-true) (setq listLays (cons item listLays)))) listLays)
(defun GetExampleTags ( / doc tagList found atts tag) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) tagList '() found nil) (vlax-for lay (vla-get-Layouts doc) (if (not found) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (foreach att (vlax-invoke blk 'GetAttributes) (setq tag (strcase (vla-get-TagString att))) (if (and (/= tag "DES_NUM") (not (wcmatch tag "REV_?,DATA_?,DESC_?"))) (setq tagList (cons tag tagList)))) (setq found T)))))) (vl-sort tagList '<))
(defun GetMaxRevision (blk / revLetter revDate checkRev finalRev finalDate) (setq finalRev "-" finalDate "-") (foreach letra '("E" "D" "C" "B" "A") (if (= finalRev "-") (progn (setq checkRev (GetAttValue blk (strcat "REV_" letra))) (if (and (/= checkRev "") (/= checkRev " ")) (progn (setq finalRev checkRev) (setq finalDate (GetAttValue blk (strcat "DATA_" letra)))))))) (list finalRev finalDate))
(defun FormatNum (n) (if (< n 10) (strcat "0" (itoa n)) (itoa n)))
(defun CleanCSV (str) (setq str (vl-string-translate ";" "," str)) (vl-string-trim " \"" str))
(defun EscapeJSON (str / i char result len) (setq result "" len (strlen str) i 1) (while (<= i len) (setq char (substr str i 1)) (cond ((= char "\\") (setq result (strcat result "\\\\"))) ((= char "\"") (setq result (strcat result "\\\""))) (t (setq result (strcat result char)))) (setq i (1+ i))) result)
(defun StringUnescape (str / result i char nextChar len) (setq result "" len (strlen str) i 1) (while (<= i len) (setq char (substr str i 1)) (if (and (= char "\\") (< i len)) (progn (setq nextChar (substr str (1+ i) 1)) (cond ((= nextChar "\\") (setq result (strcat result "\\"))) ((= nextChar "\"") (setq result (strcat result "\""))) (t (setq result (strcat result char)))) (setq i (1+ i))) (setq result (strcat result char))) (setq i (1+ i))) result)