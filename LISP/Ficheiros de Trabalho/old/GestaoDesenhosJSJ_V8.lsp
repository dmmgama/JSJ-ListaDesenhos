;; ============================================================================
;; FERRAMENTA UNIFICADA: GESTAO DESENHOS JSJ (V8 - TEMPLATE ROUNDTRIP)
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
    (princ "\n 4. Gerar Lista via TEMPLATE (Usa o teu modelo)")
    (princ "\n 5. Importar Excel (Normal ou Template)") ;; ATUALIZADO
    (princ "\n 0. Sair")
    (princ "\n==============================================")

    (initget "1 2 3 4 5 0")
    (setq opt (getkword "\nEscolha uma opção [1/2/3/4/5/0]: "))

    (cond
      ((= opt "1") (Run_MasterImport_Menu))
      ((= opt "2") (Run_ExportJSON))
      ((= opt "3") (Run_GenerateExcel_Pro))
      ((= opt "4") (Run_GenerateExcel_FromTemplate))
      ((= opt "5") (Run_ImportExcel_Flexible)) ;; NOVA FUNÇÃO UNIFICADA
      ((= opt "0") (setq loop nil))
      ((= opt nil) (setq loop nil)) 
    )
  )
  (graphscr)
  (princ "\nGestao Desenhos JSJ Terminada.")
  (princ)
)

;; ============================================================================
;; MÓDULO 4 & 5: IMPORTAR EXCEL FLEXÍVEL (NORMAL OU TEMPLATE)
;; ============================================================================
(defun Run_ImportExcel_Flexible ( / xlsFile startCellStr startRow startCol excelApp wb sheet cells r valHandle valTipo valNum valTit valRev valData countUpdates)
  
  (setq xlsFile (getfiled "Selecione o ficheiro Excel" "" "xlsx;xls" 4))
  
  (if (and xlsFile (findfile xlsFile))
    (progn
      ;; PERGUNTA A CÉLULA DE INÍCIO
      (setq startCellStr (getstring "\nIndique a célula onde começam os dados (ex: B10) [Enter='A2']: "))
      (if (= startCellStr "") (setq startCellStr "A2"))

      (princ "\nA abrir Excel... ")
      (setq excelApp (vlax-get-or-create-object "Excel.Application"))
      
      (if excelApp
        (progn
          (vla-put-visible excelApp :vlax-true)
          (setq wb (vlax-invoke-method (vlax-get-property excelApp 'Workbooks) 'Open xlsFile))
          (setq sheet (vlax-get-property wb 'ActiveSheet))
          
          ;; CALCULA LINHA E COLUNA INICIAL
          (if (vl-catch-all-error-p (setq cellObj (vl-catch-all-apply 'vlax-get-property (list sheet 'Range startCellStr))))
             (progn (alert "Célula inválida! A usar A2.") (setq cellObj (vlax-get-property sheet 'Range "A2")))
          )
          (setq startRow (VariantToInt (vlax-get-property cellObj 'Row)))
          (setq startCol (VariantToInt (vlax-get-property cellObj 'Column)))
          (vlax-release-object cellObj)

          (princ "\nA atualizar CAD... ")
          (setq cells (vlax-get-property sheet 'Cells))
          (setq countUpdates 0)

          ;; LOOP DE LEITURA (Lê até encontrar um ID vazio na coluna relativa +5)
          ;; Estrutura relativa: 0=Tipo, 1=Num, 2=Tit, 3=Rev, 4=Data, 5=ID
          (setq r 0)
          (while r 
             ;; Lê ID (Coluna + 5)
             (setq valHandle (GetCellText cells (+ startRow r) (+ startCol 5)))
             
             ;; Critério de paragem: Se ID e Num estiverem vazios, acabou a lista
             (if (or (= valHandle "") (= valHandle nil))
               (setq r nil) ;; Sai do loop
               (progn
                 ;; Lê restantes dados
                 (setq valTipo (GetCellText cells (+ startRow r) (+ startCol 0)))
                 (setq valNum  (GetCellText cells (+ startRow r) (+ startCol 1)))
                 (setq valTit  (GetCellText cells (+ startRow r) (+ startCol 2)))
                 (setq valRev  (GetCellText cells (+ startRow r) (+ startCol 3)))
                 (setq valData (GetCellText cells (+ startRow r) (+ startCol 4)))
                 
                 ;; Atualiza
                 (UpdateBlockByHandleAndData valHandle valTipo valNum valTit valRev valData)
                 (setq countUpdates (1+ countUpdates))
                 (setq r (1+ r))
               )
             )
          )
          
          (vlax-invoke-method wb 'Close :vlax-false)
          (vlax-invoke-method excelApp 'Quit)
          (ReleaseObject cells) (ReleaseObject sheet) (ReleaseObject wb) (ReleaseObject excelApp)
          
          (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport)
          (alert (strcat "Importação Concluída!\n" (itoa countUpdates) " desenhos analisados."))
        )
        (alert "Erro ao iniciar Excel.")
      )
    )
    (princ "\nCancelado.")
  )
  (princ)
)

;; ============================================================================
;; MÓDULO EXPORTAR EXCEL VIA TEMPLATE (CORRIGIDO)
;; ============================================================================
(defun Run_GenerateExcel_FromTemplate ( / doc templateFile outputFile startCellStr excelApp wb sheet cellObj cells startRow startCol i layoutList dataList sortMode sortOrder valTipo valNum valTit maxRev revLetra revData valHandle)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))

  (setq templateFile (getfiled "Selecione o ficheiro TEMPLATE" "" "xlsx;xls" 4))
  (if (and templateFile (findfile templateFile))
    (progn
      (setq outputFile (getfiled "Guardar Resultado Como..." "" "xlsx" 1))
      (if outputFile
        (progn
          (setq startCellStr (getstring "\nIndique a célula inicial (ex: B10) [Enter='A2']: "))
          (if (= startCellStr "") (setq startCellStr "A2")) 

          (princ "\nA recolher dados... ")
          (setq dataList '())
          (setq layoutList (GetLayoutsRaw doc))
          (foreach lay layoutList
            (vlax-for blk (vla-get-Block lay)
              (if (IsTargetBlock blk)
                (progn
                  (setq valTipo (GetAttValue blk "TIPO")) (setq valNum (GetAttValue blk "DES_NUM")) (setq valTit (GetAttValue blk "TITULO"))
                  (setq maxRev (GetMaxRevision blk)) (setq revLetra (car maxRev)) (setq revData (cadr maxRev))
                  (setq valHandle (vla-get-Handle blk))
                  (setq dataList (cons (list valTipo valNum valTit revLetra revData valHandle) dataList))
                )
              )
            )
          )
          ;; Ordenação (Simplificada)
          (setq dataList (vl-sort dataList '(lambda (a b) (< (strcase (nth 1 a)) (strcase (nth 1 b))))))

          (princ "\nA preencher Template... ")
          (setq excelApp (vlax-get-or-create-object "Excel.Application"))
          
          (if excelApp
            (progn
              (vla-put-visible excelApp :vlax-true)
              (setq wb (vlax-invoke-method (vlax-get-property excelApp 'Workbooks) 'Open templateFile))
              (setq sheet (vlax-get-property wb 'ActiveSheet))
              
              ;; Resolve Célula Inicial
              (if (vl-catch-all-error-p (setq cellObj (vl-catch-all-apply 'vlax-get-property (list sheet 'Range startCellStr))))
                (progn (alert "Célula inválida! A usar A2.") (setq cellObj (vlax-get-property sheet 'Range "A2")))
              )
              (setq startRow (VariantToInt (vlax-get-property cellObj 'Row)))
              (setq startCol (VariantToInt (vlax-get-property cellObj 'Column)))
              (vlax-release-object cellObj)

              (setq cells (vlax-get-property sheet 'Cells))
              (setq i 0)
              (foreach row dataList
                (PutCell cells (+ startRow i) (+ startCol 0) (nth 0 row))
                (PutCell cells (+ startRow i) (+ startCol 1) (nth 1 row))
                (PutCell cells (+ startRow i) (+ startCol 2) (nth 2 row))
                (PutCell cells (+ startRow i) (+ startCol 3) (nth 3 row))
                (PutCell cells (+ startRow i) (+ startCol 4) (nth 4 row))
                (PutCell cells (+ startRow i) (+ startCol 5) (nth 5 row))
                (setq i (1+ i))
              )

              (vlax-invoke-method wb 'SaveAs outputFile)
              (alert "Sucesso! Lista gerada.")
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
;; FUNÇÕES CORE (ATUALIZAÇÃO E LEITURA)
;; ============================================================================
(defun UpdateBlockByHandleAndData (handle tipo num tit rev dataStr / ename obj atts revTag dataTag)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle)))
  (if (and ename (setq obj (vlax-ename->vla-object ename)))
    (if (IsTargetBlock obj)
      (progn
        (UpdateSingleTag handle "TIPO" tipo) (UpdateSingleTag handle "DES_NUM" num) (UpdateSingleTag handle "TITULO" tit)
        (if (and rev (/= rev "") (/= rev "-"))
          (progn (setq revTag (strcat "REV_" rev)) (setq dataTag (strcat "DATA_" rev)) (UpdateSingleTag handle revTag rev) (UpdateSingleTag handle dataTag dataStr))
        )
        (princ ".")
      )
    )
  )
)

;; ============================================================================
;; FUNÇÕES AUXILIARES (BLINDADAS PARA ERRO VARIANT)
;; ============================================================================

;; Helper para converter Variants do Excel para Inteiros Lisp
(defun VariantToInt (var)
  (if (= (type var) 'variant) (setq var (vlax-variant-value var)))
  (if (= (type var) 'INT) var (atoi (vl-princ-to-string var)))
)

(defun PutCell (cells row col val / item)
  ;; Tenta escrever valor. Se falhar, tenta converter para string.
  (if (vl-catch-all-error-p 
        (vl-catch-all-apply 'vlax-put-property (list cells 'Item row col val)))
    (vlax-put-property cells 'Item row col (vl-princ-to-string val))
  )
)

(defun GetCellText (cells row col / item val)
  (setq item (vlax-get-property cells 'Item row col))
  ;; Variant handling
  (if (= (type item) 'variant) (setq item (vlax-variant-value item)))
  (setq val (vlax-get-property item 'Text))
  (vlax-release-object item)
  val
)

;; (Outras auxiliares mantidas da V7)
(defun ReleaseObject (obj) (if (and obj (not (vlax-object-released-p obj))) (vlax-release-object obj)))
(defun IsTargetBlock (blk) (and (= (vla-get-ObjectName blk) "AcDbBlockReference") (= (strcase (vla-get-EffectiveName blk)) "LEGENDA_JSJ_V1")))
(defun GetAttValue (blk tag / atts val) (setq atts (vlax-invoke blk 'GetAttributes) val "") (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (setq val (vla-get-TextString att)))) val)
(defun UpdateSingleTag (handle tag val / ename obj atts) (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle))) (if (and ename (setq obj (vlax-ename->vla-object ename))) (progn (setq atts (vlax-invoke obj 'GetAttributes)) (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (vla-put-TextString att val))) (vla-Update obj))))
(defun UpdateBlockByHandle (handle pairList / ename obj atts tagVal foundVal) (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle))) (if (and ename (setq obj (vlax-ename->vla-object ename))) (if (and (= (vla-get-ObjectName obj) "AcDbBlockReference") (= (vla-get-HasAttributes obj) :vlax-true)) (foreach att (vlax-invoke obj 'GetAttributes) (setq tagVal (strcase (vla-get-TagString att)) foundVal (cdr (assoc tagVal pairList))) (if foundVal (vla-put-TextString att foundVal))))))
(defun ApplyGlobalValue (targetTag targetVal / doc) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))) (vlax-for lay (vla-get-Layouts doc) (if (/= (vla-get-ModelType lay) :vlax-true) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (foreach att (vlax-invoke blk 'GetAttributes) (if (= (strcase (vla-get-TagString att)) targetTag) (vla-put-TextString att targetVal))))))) (vla-Regen doc acActiveViewport))
(defun GetDrawingList ( / doc listOut atts desNum tipo) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) listOut '()) (vlax-for lay (vla-get-Layouts doc) (if (/= (vla-get-ModelType lay) :vlax-true) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (setq desNum (GetAttValue blk "DES_NUM") tipo (GetAttValue blk "TIPO")) (if (= desNum "") (setq desNum "??")) (if (= tipo "") (setq tipo "ND")) (setq listOut (cons (list (vla-get-Handle blk) desNum (vla-get-Name lay) tipo) listOut))))))) (reverse listOut))
(defun GetLayoutsRaw (doc / lays listLays) (setq lays (vla-get-Layouts doc) listLays '()) (vlax-for item lays (if (/= (vla-get-ModelType item) :vlax-true) (setq listLays (cons item listLays)))) listLays)
(defun GetExampleTags ( / doc tagList found atts tag) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) tagList '() found nil) (vlax-for lay (vla-get-Layouts doc) (if (not found) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (foreach att (vlax-invoke blk 'GetAttributes) (setq tag (strcase (vla-get-TagString att))) (if (and (/= tag "DES_NUM") (not (wcmatch tag "REV_?,DATA_?,DESC_?"))) (setq tagList (cons tag tagList)))) (setq found T)))))) (vl-sort tagList '<))
(defun GetMaxRevision (blk / revLetter revDate checkRev finalRev finalDate) (setq finalRev "-" finalDate "-") (foreach letra '("E" "D" "C" "B" "A") (if (= finalRev "-") (progn (setq checkRev (GetAttValue blk (strcat "REV_" letra))) (if (and (/= checkRev "") (/= checkRev " ")) (progn (setq finalRev checkRev) (setq finalDate (GetAttValue blk (strcat "DATA_" letra)))))))) (list finalRev finalDate))
(defun FormatNum (n) (if (< n 10) (strcat "0" (itoa n)) (itoa n)))
(defun CleanCSV (str) (setq str (vl-string-translate ";" "," str)) (vl-string-trim " \"" str))
(defun EscapeJSON (str / i char result len) (setq result "" len (strlen str) i 1) (while (<= i len) (setq char (substr str i 1)) (cond ((= char "\\") (setq result (strcat result "\\\\"))) ((= char "\"") (setq result (strcat result "\\\""))) (t (setq result (strcat result char)))) (setq i (1+ i))) result)
(defun StringUnescape (str / result i char nextChar len) (setq result "" len (strlen str) i 1) (while (<= i len) (setq char (substr str i 1)) (if (and (= char "\\") (< i len)) (progn (setq nextChar (substr str (1+ i) 1)) (cond ((= nextChar "\\") (setq result (strcat result "\\"))) ((= nextChar "\"") (setq result (strcat result "\""))) (t (setq result (strcat result char)))) (setq i (1+ i))) (setq result (strcat result char))) (setq i (1+ i))) result)

;; --- PLACEHOLDERS PARA MODULO 1 E 2 PARA FICAR COMPLETO SE QUISERES COLAR O RESTO ---
(defun Run_ExportJSON ( / ) (princ "\nJSON Export (Use codigo V7).")) 
(defun Run_GenerateExcel_Pro ( / ) (princ "\nUse codigo V7 para excel do zero."))