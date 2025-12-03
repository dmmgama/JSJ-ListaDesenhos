;; ============================================================================
;; FERRAMENTA UNIFICADA: GESTAO DESENHOS JSJ
;; Comandos: Master Import, Exportar JSON, Gerar Lista
;; ============================================================================

(defun c:GESTAODESENHOSJSJ ( / loop opt)
  (vl-load-com)
  (setq loop T)

  (while loop
    (textscr)
    (princ "\n\n==============================================")
    (princ "\n          GESTAO DESENHOS JSJ - MENU          ")
    (princ "\n==============================================")
    (princ "\n 1. Modificar Legendas (Master Import / Numeração)")
    (princ "\n 2. Exportar JSON (Backup dos dados)")
    (princ "\n 3. Gerar Lista de Desenhos (Excel/CSV)")
    (princ "\n 0. Sair")
    (princ "\n==============================================")

    (initget "1 2 3 0")
    (setq opt (getkword "\nEscolha uma opção [1/2/3/0]: "))

    (cond
      ((= opt "1") (Run_MasterImport_Menu))
      ((= opt "2") (Run_ExportJSON))
      ((= opt "3") (Run_GenerateList))
      ((= opt "0") (setq loop nil))
      ((= opt nil) (setq loop nil)) 
    )
  )
  (graphscr)
  (princ "\nGestao Desenhos JSJ Terminada.")
  (princ)
)

;; ============================================================================
;; MÓDULO 1: MODIFICAR LEGENDAS (ANTIGO MASTER IMPORT V2)
;; ============================================================================

(defun Run_MasterImport_Menu ( / loopSub optSub)
  (setq loopSub T)
  (while loopSub
    (textscr)
    (princ "\n\n   --- SUB-MENU: MODIFICAR LEGENDAS ---")
    (princ "\n   1. Importar JSON (Upload de dados)")
    (princ "\n   2. Definir Campos Gerais (Global)")
    (princ "\n   3. Alterar Desenhos (Individual)")
    (princ "\n   4. Numerar por TIPO (01, 02... por grupo)")
    (princ "\n   5. Numerar SEQUENCIAL (01...XX por tabs)")
    (princ "\n   0. Voltar ao Menu Principal")
    (princ "\n   ------------------------------------")

    (initget "1 2 3 4 5 0")
    (setq optSub (getkword "\n   Opção [1/2/3/4/5/0]: "))

    (cond
      ((= optSub "1") (ProcessJSONImport))
      ((= optSub "2") (ProcessGlobalVariables))
      ((= optSub "3") (ProcessManualReview))
      ((= optSub "4") (AutoNumberByType))
      ((= optSub "5") (AutoNumberSequential))
      ((= optSub "0") (setq loopSub nil)) ;; Sai do loopSub, volta ao Main
      ((= optSub nil) (setq loopSub nil))
    )
  )
)

;; --- LÓGICAS DO MASTER IMPORT ---

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
      (alert (strcat "Importação Concluída.\nBlocos atualizados: " (itoa countUpdates)))
    )
    (princ "\nCancelado.")
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

(defun ProcessManualReview ( / loop drawList i item userIdx selectedHandle field revLet revVal)
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

(defun AutoNumberByType ( / doc dataList blk typeVal handleVal tabOrd sortedList curType count i)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq dataList '())
  (princ "\n\nA analisar Tipos e Layouts...")
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (IsTargetBlock blk)
          (progn
            (setq typeVal (GetAttValue blk "TIPO"))
            (if (= typeVal "") (setq typeVal "INDEFINIDO")) 
            (setq handleVal (vla-get-Handle blk))
            (setq tabOrd (vla-get-TabOrder lay))
            (setq dataList (cons (list typeVal tabOrd handleVal) dataList))
          )
        )
      )
    )
  )
  (setq sortedList (vl-sort dataList '(lambda (a b) (if (= (strcase (car a)) (strcase (car b))) (< (cadr a) (cadr b)) (< (strcase (car a)) (strcase (car b)))))))
  (setq curType "" count 0 i 0)
  (foreach item sortedList
    (if (/= (strcase (car item)) curType) (progn (setq curType (strcase (car item))) (setq count 1)) (setq count (1+ count)))
    (UpdateSingleTag (caddr item) "DES_NUM" (FormatNum count))
    (setq i (1+ i))
  )
  (vla-Regen doc acActiveViewport)
  (alert (strcat "Concluído!\nRenumerados " (itoa i) " desenhos por Tipo."))
)

(defun AutoNumberSequential ( / doc sortedLayouts count i)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (initget "Sim Nao")
  (if (= (getkword "\nNumerar DES_NUM sequencialmente pela ordem das Tabs? [Sim/Nao] <Nao>: ") "Sim")
    (progn
      (setq sortedLayouts (GetLayoutsRaw doc))
      (setq sortedLayouts (vl-sort sortedLayouts '(lambda (a b) (< (vla-get-TabOrder a) (vla-get-TabOrder b)))))
      (setq count 1 i 0)
      (foreach lay sortedLayouts
        (vlax-for blk (vla-get-Block lay)
          (if (IsTargetBlock blk)
            (progn (UpdateSingleTag (vla-get-Handle blk) "DES_NUM" (FormatNum count)) (setq count (1+ count)) (setq i (1+ i)))
          )
        )
      )
      (vla-Regen doc acActiveViewport)
      (alert (strcat "Concluído!\nRenumerados " (itoa i) " desenhos sequencialmente."))
    )
  )
)

;; ============================================================================
;; MÓDULO 2: EXPORTAR JSON
;; ============================================================================

(defun Run_ExportJSON ( / doc path name jsonFile fileDes jsonList jsonItem atts idVal handleVal subList tag val escapedVal)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq path (vla-get-Path doc))
  (if (= path "") (progn (alert "Erro: Grave o desenho primeiro!") (exit)))

  (setq name (vl-filename-base (vla-get-Name doc)))
  (setq jsonFile (strcat path "\\" name "_legendas.json"))
  (setq jsonList '()) 

  (princ "\nA exportar JSON... ")

  (vlax-for layout (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType layout) :vlax-true)
      (vlax-for blk (vla-get-Block layout)
        (if (IsTargetBlock blk)
          (progn
            (setq handleVal (vla-get-Handle blk))
            (setq atts (vlax-invoke blk 'GetAttributes))
            (setq subList "" idVal "") 
            (foreach att atts
              (setq tag (vla-get-TagString att))
              (setq val (vla-get-TextString att))
              (setq escapedVal (EscapeJSON val))
              (if (= (strcase tag) "DES_NUM") (setq idVal escapedVal))
              (setq subList (strcat subList "      \"" tag "\": \"" escapedVal "\",\n"))
            )
            (if (> (strlen subList) 2) (setq subList (substr subList 1 (- (strlen subList) 2))))
            (if (= idVal "") (setq idVal (strcat "ND_" handleVal)))
            (setq jsonItem (strcat "  {\n    \"id_desenho\": \"" idVal "\",\n    \"layout_tab\": \"" (vla-get-Name layout) "\",\n    \"handle_bloco\": \"" handleVal "\",\n    \"atributos\": {\n" subList "\n    }\n  }"))
            (setq jsonList (cons jsonItem jsonList))
          )
        )
      )
    )
  )

  (if jsonList
    (progn
      (setq fileDes (open jsonFile "w"))
      (write-line "[" fileDes)
      (setq i 0)
      (foreach item (reverse jsonList) (if (> i 0) (write-line "," fileDes)) (princ item fileDes) (setq i (1+ i)))
      (write-line "\n]" fileDes)
      (close fileDes)
      (alert (strcat "Sucesso! JSON criado em:\n" jsonFile))
    )
    (alert "Aviso: Nenhuma legenda encontrada.")
  )
)

;; ============================================================================
;; MÓDULO 3: GERAR LISTA (COM FILE DIALOG)
;; ============================================================================

(defun Run_GenerateList ( / doc path name csvFile defaultName fileDes layoutList dataList sortMode sortOrder valTipo valNum valTit maxRev revLetra revData)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq path (vla-get-Path doc))
  (if (= path "") (progn (alert "Grave o desenho primeiro!") (exit)))
  (setq name (vl-filename-base (vla-get-Name doc)))
  
  ;; --- NOVO: Pede o nome do ficheiro ao utilizador ---
  (setq defaultName (strcat path "\\" name "_ListaDesenhos.csv"))
  (setq csvFile (getfiled "Guardar Lista de Desenhos" defaultName "csv" 1))

  (if csvFile
    (progn
      (princ "\nA recolher dados... ")
      (setq dataList '())
      (setq layoutList (GetLayoutsRaw doc))
      
      (foreach lay layoutList
        (vlax-for blk (vla-get-Block lay)
          (if (IsTargetBlock blk)
            (progn
              (setq valTipo (CleanCSV (GetAttValue blk "TIPO")))
              (setq valNum  (CleanCSV (GetAttValue blk "DES_NUM")))
              (setq valTit  (CleanCSV (GetAttValue blk "TITULO")))
              (setq maxRev (GetMaxRevision blk)) 
              (setq revLetra (CleanCSV (car maxRev)))
              (setq revData (CleanCSV (cadr maxRev)))
              (setq dataList (cons (list valTipo valNum valTit revLetra revData) dataList))
            )
          )
        )
      )

      ;; Perguntas de Ordenação
      (initget "Tipo Numero")
      (setq sortMode (getkword "\nOrdenar por? [Tipo/Numero] <Numero>: "))
      (if (not sortMode) (setq sortMode "Numero"))

      (if (= sortMode "Tipo")
        (progn
          (initget "Ascendente Descendente")
          (setq sortOrder (getkword "\nOrdem do TIPO? [Ascendente/Descendente] <Ascendente>: "))
          (if (not sortOrder) (setq sortOrder "Ascendente"))
        )
      )

      ;; Ordenação
      (cond
        ((= sortMode "Tipo")
         (setq dataList (vl-sort dataList '(lambda (a b)
                (if (= (strcase (nth 0 a)) (strcase (nth 0 b)))
                  (< (strcase (nth 1 a)) (strcase (nth 1 b)))
                  (if (= sortOrder "Descendente") (> (strcase (nth 0 a)) (strcase (nth 0 b))) (< (strcase (nth 0 a)) (strcase (nth 0 b))))
                ))))
        )
        ((= sortMode "Numero")
         (setq dataList (vl-sort dataList '(lambda (a b) (< (strcase (nth 1 a)) (strcase (nth 1 b))))))
        )
      )

      ;; Escrita com Proteção
      (setq fileDes (open csvFile "w"))
      (if fileDes
        (progn
          (write-line "Tipo;Número de Desenho;Título;Revisão;Data" fileDes)
          (foreach row dataList (write-line (strcat (nth 0 row) ";" (nth 1 row) ";" (nth 2 row) ";" (nth 3 row) ";" (nth 4 row)) fileDes))
          (close fileDes)
          (alert (strcat "Lista gerada com sucesso!\n" csvFile))
        )
        (alert "ERRO: Não foi possível gravar.\nVerifique se o ficheiro Excel está aberto.")
      )
    )
    (princ "\nOperação cancelada pelo utilizador.")
  )
)

;; ============================================================================
;; FUNÇÕES AUXILIARES PARTILHADAS (SHARED KERNEL)
;; ============================================================================

(defun IsTargetBlock (blk)
  (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
       (= (strcase (vla-get-EffectiveName blk)) "LEGENDA_JSJ_V1"))
)

(defun GetAttValue (blk tag / atts val)
  (setq atts (vlax-invoke blk 'GetAttributes) val "")
  (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (setq val (vla-get-TextString att))))
  val
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
            (setq desNum (GetAttValue blk "DES_NUM") tipo (GetAttValue blk "TIPO"))
            (if (= desNum "") (setq desNum "??"))
            (if (= tipo "") (setq tipo "ND"))
            (setq listOut (cons (list (vla-get-Handle blk) desNum (vla-get-Name lay) tipo) listOut))
          )
        )
      )
    )
  )
  (reverse listOut)
)

(defun GetLayoutsRaw (doc / lays listLays)
  (setq lays (vla-get-Layouts doc) listLays '())
  (vlax-for item lays (if (/= (vla-get-ModelType item) :vlax-true) (setq listLays (cons item listLays))))
  listLays
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

(defun GetMaxRevision (blk / revLetter revDate checkRev finalRev finalDate)
  (setq finalRev "-" finalDate "-")
  (foreach letra '("E" "D" "C" "B" "A")
    (if (= finalRev "-") (progn (setq checkRev (GetAttValue blk (strcat "REV_" letra))) (if (and (/= checkRev "") (/= checkRev " ")) (progn (setq finalRev checkRev) (setq finalDate (GetAttValue blk (strcat "DATA_" letra)))))))
  )
  (list finalRev finalDate)
)

(defun FormatNum (n) (if (< n 10) (strcat "0" (itoa n)) (itoa n)))
(defun CleanCSV (str) (setq str (vl-string-translate ";" "," str)) (vl-string-trim " \"" str))
(defun EscapeJSON (str / i char result len) (setq result "" len (strlen str) i 1) (while (<= i len) (setq char (substr str i 1)) (cond ((= char "\\") (setq result (strcat result "\\\\"))) ((= char "\"") (setq result (strcat result "\\\""))) (t (setq result (strcat result char)))) (setq i (1+ i))) result)
(defun StringUnescape (str / result i char nextChar len) (setq result "" len (strlen str) i 1) (while (<= i len) (setq char (substr str i 1)) (if (and (= char "\\") (< i len)) (progn (setq nextChar (substr str (1+ i) 1)) (cond ((= nextChar "\\") (setq result (strcat result "\\"))) ((= nextChar "\"") (setq result (strcat result "\""))) (t (setq result (strcat result char)))) (setq i (1+ i))) (setq result (strcat result char))) (setq i (1+ i))) result)