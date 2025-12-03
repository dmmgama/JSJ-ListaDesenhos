(defun c:MASTER_IMPORT ( / loop opt)
  (vl-load-com)
  (setq loop T)

  (while loop
    (textscr)
    (princ "\n\n==============================================")
    (princ "\n          MASTER IMPORT V2 - MENU             ")
    (princ "\n==============================================")
    (princ "\n 1. Importar JSON (Ficheiro Externo)")
    (princ "\n 2. Definir Campos Gerais (Global em todos os layouts)")
    (princ "\n 3. Alterar Desenhos (Revisões e Títulos Individuais)")
    (princ "\n 4. Numerar por TIPO (Reinicia 01 a cada Tipo)")
    (princ "\n 5. Numerar SEQUENCIAL (01 a XX pela ordem das Tabs)")
    (princ "\n 0. Sair")
    (princ "\n==============================================")

    (initget "1 2 3 4 5 0")
    (setq opt (getkword "\nEscolha uma opção [1/2/3/4/5/0]: "))

    (cond
      ((= opt "1") (ProcessJSONImport))
      ((= opt "2") (ProcessGlobalVariables))
      ((= opt "3") (ProcessManualReview))
      ((= opt "4") (AutoNumberByType))       ;; NOVA
      ((= opt "5") (AutoNumberSequential))   ;; NOVA
      ((= opt "0") (setq loop nil))
      ((= opt nil) (setq loop nil)) ;; Enter sai
    )
  )
  (graphscr)
  (princ "\nMaster Import Terminado.")
  (princ)
)

;; ============================================================================
;; NOVAS FUNÇÕES DE NUMERAÇÃO AUTOMÁTICA
;; ============================================================================

;; --- OPÇÃO 4: NUMERAR POR TIPO ---
(defun AutoNumberByType ( / doc layouts dataList blk typeVal handleVal tabOrd sortedList curType count i)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq dataList '())

  (princ "\n\nA analisar Tipos e Layouts...")
  
  ;; 1. Coletar dados: (TIPO TAB_ORDER HANDLE)
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (IsTargetBlock blk)
          (progn
            (setq typeVal (GetAttValue blk "TIPO"))
            (if (= typeVal "") (setq typeVal "INDEFINIDO")) ;; Para não falhar na ordenação
            (setq handleVal (vla-get-Handle blk))
            (setq tabOrd (vla-get-TabOrder lay))
            
            ;; Lista: (TIPO ORDEM HANDLE)
            (setq dataList (cons (list typeVal tabOrd handleVal) dataList))
          )
        )
      )
    )
  )

  ;; 2. Ordenar: Primeiro por TIPO, depois por ORDEM DA TAB
  (setq sortedList 
    (vl-sort dataList 
      '(lambda (a b)
         (if (= (strcase (car a)) (strcase (car b)))
             (< (cadr a) (cadr b)) ;; Se tipo igual, ordena por tab
             (< (strcase (car a)) (strcase (car b))) ;; Senão, ordena por tipo
         )
      )
    )
  )

  ;; 3. Aplicar Numeração
  (setq curType "" count 0 i 0)
  
  (foreach item sortedList
    (if (/= (strcase (car item)) curType)
      (progn
        (setq curType (strcase (car item)))
        (setq count 1) ;; Reset contador para novo tipo
      )
      (setq count (1+ count))
    )
    ;; Atualiza DES_NUM
    (UpdateSingleTag (caddr item) "DES_NUM" (FormatNum count))
    (setq i (1+ i))
  )
  
  (vla-Regen doc acActiveViewport)
  (alert (strcat "Concluído!\n\nForam renumerados " (itoa i) " desenhos agrupados por Tipo."))
)

;; --- OPÇÃO 5: NUMERAR SEQUENCIAL ---
(defun AutoNumberSequential ( / doc sortedLayouts count handleVal i)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  (initget "Sim Nao")
  (if (= (getkword "\nIsto vai alterar o DES_NUM de TODOS os desenhos pela ordem das Tabs. Continuar? [Sim/Nao] <Nao>: ") "Sim")
    (progn
      ;; 1. Obter Layouts ordenados
      (setq sortedLayouts (GetLayoutsSorted doc))
      (setq count 1 i 0)

      (foreach lay sortedLayouts
        (vlax-for blk (vla-get-Block lay)
          (if (IsTargetBlock blk)
            (progn
              (UpdateSingleTag (vla-get-Handle blk) "DES_NUM" (FormatNum count))
              (setq count (1+ count))
              (setq i (1+ i))
            )
          )
        )
      )
      (vla-Regen doc acActiveViewport)
      (alert (strcat "Concluído!\n\nForam renumerados " (itoa i) " desenhos sequencialmente (01, 02...)."))
    )
  )
)

;; ============================================================================
;; FUNÇÕES EXISTENTES (MANTIDAS E OTIMIZADAS)
;; ============================================================================

(defun ProcessJSONImport ( / jsonFile fileDes line posSep handleVal attList inAttributes tag rawContent cleanContent countUpdates)
  (setq jsonFile (getfiled "Selecione o ficheiro JSON" "" "json" 4))
  (if (and jsonFile (findfile jsonFile))
    (progn
      (setq fileDes (open jsonFile "r"))
      (setq handleVal nil attList '() inAttributes nil countUpdates 0)
      (princ "\nA processar JSON... ")
      (while (setq line (read-line fileDes))
        (setq line (vl-string-trim " \t" line))
        (cond
          ((vl-string-search "\"handle_bloco\":" line)
           (setq posSep (vl-string-search ":" line))
           (if posSep (progn 
             (setq rawContent (substr line (+ posSep 2)))
             (setq handleVal (vl-string-trim " \"," rawContent))
             (setq attList '()) 
           ))
          )
          ((vl-string-search "\"atributos\": {" line) (setq inAttributes T))
          ((and inAttributes (vl-string-search "}" line))
           (setq inAttributes nil)
           (if (and handleVal attList) (UpdateBlockByHandle handleVal attList))
           (setq handleVal nil)
          )
          (inAttributes
           (setq posSep (vl-string-search "\": \"" line))
           (if posSep (progn
             (setq tag (substr line 2 (- posSep 1)))
             (setq rawContent (substr line (+ posSep 5)))
             (setq cleanContent (vl-string-trim " \"," rawContent))
             (setq cleanContent (StringUnescape cleanContent))
             (setq attList (cons (cons (strcase tag) cleanContent) attList))
           ))
          )
        ) 
      ) 
      (close fileDes)
      (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport)
      (princ (strcat "Concluído. (" (itoa countUpdates) " blocos atualizados)"))
    )
    (princ "\nImportação cancelada.")
  )
)

(defun ProcessGlobalVariables ( / loop validTags selTag newVal continueLoop)
  (setq loop T)
  (setq validTags (GetExampleTags)) 
  (while loop
    (textscr)
    (princ "\n\n=== GESTOR GLOBAL ===")
    (foreach tName validTags (princ (strcat "\n • " tName)))
    (princ "\n-----------------------------------------")
    (setq selTag (strcase (getstring "\nDigite o NOME do Tag a alterar (ex: DATA): ")))
    
    (if (member selTag validTags)
      (progn
        (setq newVal (getstring T (strcat "\nNovo valor para '" selTag "' em TODOS os desenhos: ")))
        (ApplyGlobalValue selTag newVal)
      )
      (princ "\nTag inválido.")
    )
    (initget "Sim Nao")
    (setq continueLoop (getkword "\nAlterar outro campo global? [Sim/Nao] <Sim>: "))
    (if (= continueLoop "Nao") (setq loop nil))
  )
)

(defun ProcessManualReview ( / loop drawList i item userIdx selectedHandle field revLet dateVal descVal revVal)
  (setq loop T)
  (while loop
    (setq drawList (GetDrawingList))
    (textscr)
    (princ "\n\n=== LISTA DE DESENHOS ===\n")
    (setq i 0)
    (foreach item drawList
      (princ (strcat "\n " (itoa (1+ i)) ". [Des: " (cadr item) "] (" (nth 3 item) ") - Tab: " (caddr item)))
      (setq i (1+ i))
    )
    (princ "\n-------------------------------------")
    (setq userIdx (getint (strcat "\nEscolha o número (1-" (itoa i) ") ou 0 para voltar: ")))
    
    (if (and userIdx (> userIdx 0) (<= userIdx i))
      (progn
        (setq selectedHandle (car (nth (1- userIdx) drawList)))
        (initget "Tipo Titulo Revisao")
        (setq field (getkword "\nO que quer atualizar? [Tipo/Titulo/Revisao]: "))
        (cond
          ((= field "Tipo") (UpdateSingleTag selectedHandle "TIPO" (getstring T "\nNovo TIPO: ")))
          ((= field "Titulo") (UpdateSingleTag selectedHandle "TITULO" (getstring T "\nNovo TITULO: ")))
          ((= field "Revisao")
           (initget "A B C D E")
           (setq revLet (getkword "\nQual a Revisão? [A/B/C/D/E]: "))
           (if revLet (progn
               (UpdateSingleTag selectedHandle (strcat "DATA_" revLet) (getstring T "\nData: "))
               (UpdateSingleTag selectedHandle (strcat "DESC_" revLet) (getstring T "\nDescrição: "))
               (setq revVal (getstring T (strcat "\nLetra (Enter='" revLet "'): ")))
               (if (= revVal "") (setq revVal revLet))
               (UpdateSingleTag selectedHandle (strcat "REV_" revLet) revVal)
           ))
          )
        )
      )
      (setq loop nil)
    )
    (if loop (progn (initget "Sim Nao") (if (= (getkword "\nRever outro? [Sim/Nao] <Nao>: ") "Nao") (setq loop nil))))
  )
)

;; ============================================================================
;; HELPER FUNCTIONS
;; ============================================================================

(defun IsTargetBlock (blk)
  (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
       (= (strcase (vla-get-EffectiveName blk)) "LEGENDA_JSJ_V1"))
)

(defun FormatNum (n)
  (if (< n 10) (strcat "0" (itoa n)) (itoa n))
)

(defun GetAttValue (blk tag / atts val)
  (setq atts (vlax-invoke blk 'GetAttributes) val "")
  (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (setq val (vla-get-TextString att))))
  val
)

(defun GetLayoutsSorted (doc / lays listLays)
  (setq lays (vla-get-Layouts doc) listLays '())
  (vlax-for item lays (if (/= (vla-get-ModelType item) :vlax-true) (setq listLays (cons item listLays))))
  (vl-sort listLays '(lambda (a b) (< (vla-get-TabOrder a) (vla-get-TabOrder b))))
)

(defun UpdateSingleTag (handle tag val / ename obj atts tStr)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle)))
  (if (and ename (setq obj (vlax-ename->vla-object ename)))
    (progn (setq atts (vlax-invoke obj 'GetAttributes))
      (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (vla-put-TextString att val)))
      (vla-Update obj)
    )
  )
)

(defun UpdateBlockByHandle (handle pairList / ename obj atts tagVal foundVal)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle)))
  (if (and ename (setq obj (vlax-ename->vla-object ename)))
    (if (and (= (vla-get-ObjectName obj) "AcDbBlockReference") (= (vla-get-HasAttributes obj) :vlax-true))
      (foreach att (vlax-invoke obj 'GetAttributes)
        (setq tagVal (strcase (vla-get-TagString att)) foundVal (cdr (assoc tagVal pairList)))
        (if foundVal (vla-put-TextString att foundVal))
      )
    )
  )
)

(defun ApplyGlobalValue (targetTag targetVal / doc)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (IsTargetBlock blk)
          (foreach att (vlax-invoke blk 'GetAttributes)
            (if (= (strcase (vla-get-TagString att)) targetTag) (vla-put-TextString att targetVal))
          )
        )
      )
    )
  )
  (vla-Regen doc acActiveViewport)
)

(defun GetDrawingList ( / doc listOut atts desNum tipo)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) listOut '())
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (IsTargetBlock blk)
          (progn
            (setq desNum "??" tipo "ND")
            (foreach att (vlax-invoke blk 'GetAttributes)
              (if (= (strcase (vla-get-TagString att)) "DES_NUM") (setq desNum (vla-get-TextString att)))
              (if (= (strcase (vla-get-TagString att)) "TIPO") (setq tipo (vla-get-TextString att)))
            )
            ;; Adiciona à lista: (Handle Num LayoutName Tipo)
            (setq listOut (cons (list (vla-get-Handle blk) desNum (vla-get-Name lay) tipo) listOut))
          )
        )
      )
    )
  )
  (reverse listOut)
)

(defun GetExampleTags ( / doc tagList found atts tag)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) tagList '() found nil)
  (vlax-for lay (vla-get-Layouts doc)
    (if (not found)
      (vlax-for blk (vla-get-Block lay)
        (if (IsTargetBlock blk)
          (progn
            (foreach att (vlax-invoke blk 'GetAttributes)
              (setq tag (strcase (vla-get-TagString att)))
              (if (and (/= tag "DES_NUM") (not (wcmatch tag "REV_?,DATA_?,DESC_?"))) (setq tagList (cons tag tagList)))
            ) (setq found T)
          )
        )
      )
    )
  )
  (vl-sort tagList '<)
)

(defun StringUnescape (str / result i char nextChar len)
  (setq result "" len (strlen str) i 1)
  (while (<= i len)
    (setq char (substr str i 1))
    (if (and (= char "\\") (< i len))
      (progn (setq nextChar (substr str (1+ i) 1))
        (cond ((= nextChar "\\") (setq result (strcat result "\\"))) ((= nextChar "\"") (setq result (strcat result "\""))) (t (setq result (strcat result char))))
        (setq i (1+ i)) 
      ) (setq result (strcat result char))
    ) (setq i (1+ i))
  ) result
)