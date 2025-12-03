;; ============================================================================
;; FERRAMENTA UNIFICADA: GESTAO DESENHOS JSJ (V12 - CSV ROBUSTO)
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
    (princ "\n 3. Gerar Lista CSV (Excel Simples)")   ;; ALTERADO
    (princ "\n 4. Importar Lista CSV (Atualizar CAD)") ;; ALTERADO
    (princ "\n 0. Sair")
    (princ "\n==============================================")

    (initget "1 2 3 4 0")
    (setq opt (getkword "\nEscolha uma opção [1/2/3/4/0]: "))

    (cond
      ((= opt "1") (Run_MasterImport_Menu))
      ((= opt "2") (Run_ExportJSON))
      ((= opt "3") (Run_GenerateCSV))
      ((= opt "4") (Run_ImportCSV))
      ((= opt "0") (setq loop nil))
      ((= opt nil) (setq loop nil)) 
    )
  )
  (graphscr)
  (princ "\nGestao Desenhos JSJ Terminada.")
  (princ)
)

;; ============================================================================
;; MÓDULO 3: GERAR LISTA CSV (NOVA LÓGICA ESTÁVEL)
;; ============================================================================
(defun Run_GenerateCSV ( / doc path name defaultName csvFile fileDes layoutList dataList sortMode sortOrder valTipo valNum valTit maxRev revLetra revData valHandle)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  ;; 1. DEFINIR CAMINHO (Pasta do Desenho)
  (setq path (vla-get-Path doc))
  (if (= path "") (progn (alert "Erro: Grave o desenho primeiro!") (exit)))
  (setq name (vl-filename-base (vla-get-Name doc)))
  (setq defaultName (strcat path "\\" name "_Lista.csv"))

  ;; 2. SELECIONAR FICHEIRO (Abre na pasta do desenho)
  (setq csvFile (getfiled "Guardar Lista CSV" defaultName "csv" 1))

  (if csvFile
    (progn
      (princ "\nA recolher dados... ")
      (setq dataList '())
      (setq layoutList (GetLayoutsRaw doc))
      
      (foreach lay layoutList
        (vlax-for blk (vla-get-Block lay)
          (if (IsTargetBlock blk)
            (progn
              ;; Obtém valores e LIMPA (remove ; para não partir o CSV)
              (setq valTipo (CleanCSV (GetAttValue blk "TIPO")))
              (setq valNum  (CleanCSV (GetAttValue blk "DES_NUM")))
              (setq valTit  (CleanCSV (GetAttValue blk "TITULO")))
              (setq maxRev (GetMaxRevision blk)) 
              (setq revLetra (CleanCSV (car maxRev)))
              (setq revData (CleanCSV (cadr maxRev)))
              (setq valHandle (vla-get-Handle blk))
              
              (setq dataList (cons (list valHandle valTipo valNum valTit revLetra revData) dataList))
            )
          )
        )
      )

      ;; PERGUNTAS DE ORDENAÇÃO
      (initget "Tipo Numero")
      (setq sortMode (getkword "\nOrdenar por? [Tipo/Numero] <Numero>: "))
      (if (not sortMode) (setq sortMode "Numero"))

      (cond
        ((= sortMode "Tipo") 
         (setq dataList (vl-sort dataList '(lambda (a b) 
            (if (= (strcase (nth 1 a)) (strcase (nth 1 b))) 
                (< (strcase (nth 2 a)) (strcase (nth 2 b))) 
                (< (strcase (nth 1 a)) (strcase (nth 1 b))))))))
        ((= sortMode "Numero") 
         (setq dataList (vl-sort dataList '(lambda (a b) (< (strcase (nth 2 a)) (strcase (nth 2 b)))))))
      )

      ;; 3. ESCREVER CSV (Sem Excel ActiveX - Zero Erros)
      (setq fileDes (open csvFile "w"))
      (if fileDes
        (progn
          ;; Cabeçalho (Ponto e virgula para Excel PT)
          (write-line "ID_CAD;TIPO;NUMERO;TITULO;REVISAO;DATA" fileDes)
          
          (foreach row dataList
            (write-line (strcat (nth 0 row) ";" (nth 1 row) ";" (nth 2 row) ";" (nth 3 row) ";" (nth 4 row) ";" (nth 5 row)) fileDes)
          )
          (close fileDes)
          (alert (strcat "Sucesso! Ficheiro criado:\n" csvFile "\n\nPode abrir diretamente no Excel."))
        )
        (alert "Erro: O ficheiro CSV está aberto no Excel? Feche-o e tente de novo.")
      )
    )
    (princ "\nCancelado.")
  )
  (princ)
)

;; ============================================================================
;; MÓDULO 4: IMPORTAR LISTA CSV
;; ============================================================================
(defun Run_ImportCSV ( / doc path defaultName csvFile fileDes line dataList parts valHandle valTipo valNum valTit valRev valData countUpdates)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  ;; Definir caminho padrão
  (setq path (vla-get-Path doc))
  (setq name (vl-filename-base (vla-get-Name doc)))
  (setq defaultName (strcat path "\\" name "_Lista.csv"))

  (setq csvFile (getfiled "Selecione o ficheiro CSV" defaultName "csv" 4))

  (if (and csvFile (findfile csvFile))
    (progn
      (setq fileDes (open csvFile "r"))
      (if fileDes
        (progn
          (princ "\nA processar CSV... ")
          (setq countUpdates 0)
          
          ;; Ler cabeçalho e ignorar
          (read-line fileDes)

          ;; Ler linhas
          (while (setq line (read-line fileDes))
            ;; Função Split String (Manual para Lisp)
            (setq parts (StrSplit line ";"))
            
            ;; Verifica se tem colunas suficientes (minimo 6)
            (if (>= (length parts) 6)
              (progn
                (setq valHandle (nth 0 parts))
                (setq valTipo   (nth 1 parts))
                (setq valNum    (nth 2 parts))
                (setq valTit    (nth 3 parts))
                (setq valRev    (nth 4 parts))
                (setq valData   (nth 5 parts))

                (if (and valHandle (/= valHandle ""))
                   (progn
                      (UpdateBlockByHandleAndData valHandle valTipo valNum valTit valRev valData)
                      (setq countUpdates (1+ countUpdates))
                   )
                )
              )
            )
          )
          (close fileDes)
          (vla-Regen doc acActiveViewport)
          (alert (strcat "Concluído!\n" (itoa countUpdates) " desenhos atualizados."))
        )
        (alert "Erro ao abrir ficheiro. Verifique se está aberto noutro programa.")
      )
    )
    (princ "\nCancelado.")
  )
  (princ)
)

;; ============================================================================
;; FUNÇÕES AUXILIARES (CORE + SPLIT CSV)
;; ============================================================================

;; Função para partir string por delimitador (CSV Parser)
(defun StrSplit (str del / pos len lst)
  (setq len (strlen del))
  (while (setq pos (vl-string-search del str))
    (setq lst (cons (substr str 1 pos) lst)
          str (substr str (+ 1 pos len)))
  )
  (reverse (cons str lst))
)

(defun CleanCSV (str)
  (if (= str nil) (setq str ""))
  (setq str (vl-string-translate ";" "," str)) ;; Troca ; por ,
  (vl-string-trim " \"" str) ;; Remove aspas e espaços
)

(defun UpdateBlockByHandleAndData (handle tipo num tit rev dataStr / ename obj atts revTag dataTag)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle)))
  (if (and ename (setq obj (vlax-ename->vla-object ename)))
    (if (IsTargetBlock obj)
      (progn
        (UpdateSingleTag handle "TIPO" tipo)
        (UpdateSingleTag handle "DES_NUM" num)
        (UpdateSingleTag handle "TITULO" tit)
        ;; Lógica de Revisão
        (if (and rev (/= rev "") (/= rev "-"))
          (progn 
             (setq revTag (strcat "REV_" rev)) 
             (setq dataTag (strcat "DATA_" rev)) 
             (UpdateSingleTag handle revTag rev) 
             (UpdateSingleTag handle dataTag dataStr)
          )
        )
        (princ ".")
      )
    )
  )
)

;; --- FUNÇÕES EXISTENTES (MANTIDAS) ---
(defun Run_MasterImport_Menu ( / loopSub optSub) (setq loopSub T) (while loopSub (textscr) (princ "\n\n   --- SUB-MENU ---") (princ "\n   1. Importar JSON") (princ "\n   2. Definir Campos Gerais") (princ "\n   3. Alterar Desenhos") (princ "\n   4. Numerar TIPO") (princ "\n   5. Numerar SEQUENCIAL") (princ "\n   0. Voltar") (initget "1 2 3 4 5 0") (setq optSub (getkword "\n   Opção: ")) (cond ((= optSub "1") (ProcessJSONImport)) ((= optSub "2") (ProcessGlobalVariables)) ((= optSub "3") (ProcessManualReview)) ((= optSub "4") (AutoNumberByType)) ((= optSub "5") (AutoNumberSequential)) ((= optSub "0") (setq loopSub nil)) ((= optSub nil) (setq loopSub nil)))))
(defun Run_ExportJSON ( / ) (princ "\nJSON Export.")) ;; (Copia o codigo V7 se precisares)

(defun ProcessJSONImport ( / jsonFile fileDes line posSep handleVal attList inAttributes tag rawContent cleanContent countUpdates) (setq jsonFile (getfiled "Selecione JSON" "" "json" 4)) (if (and jsonFile (findfile jsonFile)) (progn (setq fileDes (open jsonFile "r")) (setq handleVal nil attList '() inAttributes nil countUpdates 0) (princ "\nA processar JSON... ") (while (setq line (read-line fileDes)) (setq line (vl-string-trim " \t" line)) (cond ((vl-string-search "\"handle_bloco\":" line) (setq posSep (vl-string-search ":" line)) (if posSep (progn (setq rawContent (substr line (+ posSep 2))) (setq handleVal (vl-string-trim " \"," rawContent)) (setq attList '()) ))) ((vl-string-search "\"atributos\": {" line) (setq inAttributes T)) ((and inAttributes (vl-string-search "}" line)) (setq inAttributes nil) (if (and handleVal attList) (UpdateBlockByHandle handleVal attList)) (setq handleVal nil)) (inAttributes (setq posSep (vl-string-search "\": \"" line)) (if posSep (progn (setq tag (substr line 2 (- posSep 1))) (setq rawContent (substr line (+ posSep 5))) (setq cleanContent (vl-string-trim " \"," rawContent)) (setq cleanContent (StringUnescape cleanContent)) (setq attList (cons (cons (strcase tag) cleanContent) attList))))))) (close fileDes) (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport) (alert (strcat "Concluido: " (itoa countUpdates)))) (princ "\nCancelado.")))
(defun ProcessGlobalVariables ( / loop validTags selTag newVal continueLoop) (setq loop T validTags (GetExampleTags)) (while loop (textscr) (princ "\n\n=== GESTOR GLOBAL ===") (foreach tName validTags (princ (strcat "\n • " tName))) (setq selTag (strcase (getstring "\nDigite o NOME do Tag: "))) (if (member selTag validTags) (progn (setq newVal (getstring T (strcat "\nNovo valor: "))) (ApplyGlobalValue selTag newVal)) (princ "\nTag inválido.")) (initget "Sim Nao") (setq continueLoop (getkword "\nOutro? [Sim/Nao] <Sim>: ")) (if (= continueLoop "Nao") (setq loop nil))))
(defun ProcessManualReview ( / loop drawList i item userIdx selectedHandle field revLet revVal) (setq loop T) (while loop (setq drawList (GetDrawingList)) (textscr) (princ "\n\n=== LISTA DE DESENHOS ===\n") (setq i 0) (foreach item drawList (princ (strcat "\n " (itoa (1+ i)) ". [Des: " (cadr item) "] (" (nth 3 item) ") - Tab: " (caddr item))) (setq i (1+ i))) (setq userIdx (getint (strcat "\nEscolha o numero (1-" (itoa i) ") ou 0: "))) (if (and userIdx (> userIdx 0) (<= userIdx i)) (progn (setq selectedHandle (car (nth (1- userIdx) drawList))) (initget "Tipo Titulo Revisao") (setq field (getkword "\nAtualizar? [Tipo/Titulo/Revisao]: ")) (cond ((= field "Tipo") (UpdateSingleTag selectedHandle "TIPO" (getstring T "\nNovo TIPO: "))) ((= field "Titulo") (UpdateSingleTag selectedHandle "TITULO" (getstring T "\nNovo TITULO: "))) ((= field "Revisao") (initget "A B C D E") (setq revLet (getkword "\nQual a Revisão? [A/B/C/D/E]: ")) (if revLet (progn (UpdateSingleTag selectedHandle (strcat "DATA_" revLet) (getstring T "\nData: ")) (UpdateSingleTag selectedHandle (strcat "DESC_" revLet) (getstring T "\nDescrição: ")) (setq revVal (getstring T (strcat "\nLetra (Enter='" revLet "'): "))) (if (= revVal "") (setq revVal revLet)) (UpdateSingleTag selectedHandle (strcat "REV_" revLet) revVal)))))) (setq loop nil)) (if loop (progn (initget "Sim Nao") (if (= (getkword "\nOutro? [Sim/Nao] <Nao>: ") "Nao") (setq loop nil))))))
(defun AutoNumberByType ( / doc dataList blk typeVal handleVal tabOrd sortedList curType count i) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))) (setq dataList '()) (princ "\n\nA analisar...") (vlax-for lay (vla-get-Layouts doc) (if (/= (vla-get-ModelType lay) :vlax-true) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (setq typeVal (GetAttValue blk "TIPO")) (if (= typeVal "") (setq typeVal "INDEFINIDO")) (setq handleVal (vla-get-Handle blk)) (setq tabOrd (vla-get-TabOrder lay)) (setq dataList (cons (list typeVal tabOrd handleVal) dataList))))))) (setq sortedList (vl-sort dataList '(lambda (a b) (if (= (strcase (car a)) (strcase (car b))) (< (cadr a) (cadr b)) (< (strcase (car a)) (strcase (car b))))))) (setq curType "" count 0 i 0) (foreach item sortedList (if (/= (strcase (car item)) curType) (progn (setq curType (strcase (car item))) (setq count 1)) (setq count (1+ count))) (UpdateSingleTag (caddr item) "DES_NUM" (FormatNum count)) (setq i (1+ i))) (vla-Regen doc acActiveViewport) (alert (strcat "Concluído: " (itoa i))))
(defun AutoNumberSequential ( / doc sortedLayouts count i) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))) (initget "Sim Nao") (if (= (getkword "\nNumerar sequencialmente? [Sim/Nao] <Nao>: ") "Sim") (progn (setq sortedLayouts (GetLayoutsRaw doc)) (setq sortedLayouts (vl-sort sortedLayouts '(lambda (a b) (< (vla-get-TabOrder a) (vla-get-TabOrder b))))) (setq count 1 i 0) (foreach lay sortedLayouts (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (UpdateSingleTag (vla-get-Handle blk) "DES_NUM" (FormatNum count)) (setq count (1+ count)) (setq i (1+ i)))))) (vla-Regen doc acActiveViewport) (alert (strcat "Concluído: " (itoa i))))))
(defun IsTargetBlock (blk) (and (= (vla-get-ObjectName blk) "AcDbBlockReference") (= (strcase (vla-get-EffectiveName blk)) "LEGENDA_JSJ_V1")))
(defun GetAttValue (blk tag / atts val) (setq atts (vlax-invoke blk 'GetAttributes) val "") (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (setq val (vla-get-TextString att)))) val)
(defun UpdateSingleTag (handle tag val / ename obj atts) (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle))) (if (and ename (setq obj (vlax-ename->vla-object ename))) (progn (setq atts (vlax-invoke obj 'GetAttributes)) (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (vla-put-TextString att val))) (vla-Update obj))))
(defun UpdateBlockByHandle (handle pairList / ename obj atts tagVal foundVal) (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle))) (if (and ename (setq obj (vlax-ename->vla-object ename))) (if (and (= (vla-get-ObjectName obj) "AcDbBlockReference") (= (vla-get-HasAttributes obj) :vlax-true)) (foreach att (vlax-invoke obj 'GetAttributes) (setq tagVal (strcase (vla-get-TagString att)) foundVal (cdr (assoc tagVal pairList))) (if foundVal (vla-put-TextString att foundVal))))))
(defun ApplyGlobalValue (targetTag targetVal / doc) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object))) (vlax-for lay (vla-get-Layouts doc) (if (/= (vla-get-ModelType lay) :vlax-true) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (foreach att (vlax-invoke blk 'GetAttributes) (if (= (strcase (vla-get-TagString att)) targetTag) (vla-put-TextString att targetVal))))))) (vla-Regen doc acActiveViewport))
(defun GetLayoutsRaw (doc / lays listLays) (setq lays (vla-get-Layouts doc) listLays '()) (vlax-for item lays (if (/= (vla-get-ModelType item) :vlax-true) (setq listLays (cons item listLays)))) listLays)
(defun GetExampleTags ( / doc tagList found atts tag) (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)) tagList '() found nil) (vlax-for lay (vla-get-Layouts doc) (if (not found) (vlax-for blk (vla-get-Block lay) (if (IsTargetBlock blk) (progn (foreach att (vlax-invoke blk 'GetAttributes) (setq tag (strcase (vla-get-TagString att))) (if (and (/= tag "DES_NUM") (not (wcmatch tag "REV_?,DATA_?,DESC_?"))) (setq tagList (cons tag tagList)))) (setq found T)))))) (vl-sort tagList '<))
(defun GetMaxRevision (blk / revLetter revDate checkRev finalRev finalDate) (setq finalRev "-" finalDate "-") (foreach letra '("E" "D" "C" "B" "A") (if (= finalRev "-") (progn (setq checkRev (GetAttValue blk (strcat "REV_" letra))) (if (and (/= checkRev "") (/= checkRev " ")) (progn (setq finalRev checkRev) (setq finalDate (GetAttValue blk (strcat "DATA_" letra)))))))) (list finalRev finalDate))
(defun FormatNum (n) (if (< n 10) (strcat "0" (itoa n)) (itoa n)))
(defun EscapeJSON (str / i char result len) (setq result "" len (strlen str) i 1) (while (<= i len) (setq char (substr str i 1)) (cond ((= char "\\") (setq result (strcat result "\\\\"))) ((= char "\"") (setq result (strcat result "\\\""))) (t (setq result (strcat result char)))) (setq i (1+ i))) result)
(defun StringUnescape (str / result i char nextChar len) (setq result "" len (strlen str) i 1) (while (<= i len) (setq char (substr str i 1)) (if (and (= char "\\") (< i len)) (progn (setq nextChar (substr str (1+ i) 1)) (cond ((= nextChar "\\") (setq result (strcat result "\\"))) ((= nextChar "\"") (setq result (strcat result "\""))) (t (setq result (strcat result char)))) (setq i (1+ i))) (setq result (strcat result char))) (setq i (1+ i))) result)