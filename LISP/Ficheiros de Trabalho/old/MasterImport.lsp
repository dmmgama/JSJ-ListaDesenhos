(defun c:MASTER_IMPORT ( / resp)
  (vl-load-com)
  
  ;; --- FASE 1: IMPORTAR JSON ---
  (initget "Sim Nao")
  (setq resp (getkword "\n[1/3] Deseja IMPORTAR dados de um ficheiro JSON? [Sim/Nao] <Sim>: "))
  (if (or (= resp "Sim") (= resp nil))
    (ProcessJSONImport)
  )

  ;; --- FASE 2: VARIÁVEIS GLOBAIS ---
  (initget "Sim Nao")
  (setq resp (getkword "\n[2/3] Deseja definir variáveis GLOBAIS (iguais em todos os layouts)? [Sim/Nao] <Nao>: "))
  (if (= resp "Sim")
    (ProcessGlobalVariables)
  )

  ;; --- FASE 3: REVISÃO MANUAL ---
  (initget "Sim Nao")
  (setq resp (getkword "\n[3/3] Deseja REVER/EDITAR desenhos individualmente? [Sim/Nao] <Nao>: "))
  (if (= resp "Sim")
    (ProcessManualReview)
  )

  (princ "\n=== Processo MASTER_IMPORT Terminado === ")
  (princ)
)

;; ============================================================================
;; FUNÇÕES PRINCIPAIS DE PROCESSO
;; ============================================================================

;; --- PROCESSO 1: JSON ---
(defun ProcessJSONImport ( / jsonFile fileDes line posSep handleVal attList inAttributes tag rawContent cleanContent countUpdates)
  (setq jsonFile (getfiled "Selecione o ficheiro JSON" "" "json" 4))
  (if (and jsonFile (findfile jsonFile))
    (progn
      (setq fileDes (open jsonFile "r"))
      (setq handleVal nil)
      (setq attList '())
      (setq inAttributes nil)
      (setq countUpdates 0)
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
    (princ "\nImportação JSON cancelada.")
  )
)

;; --- PROCESSO 2: GLOBAIS ---
(defun ProcessGlobalVariables ( / loop validTags selTag newVal continueLoop)
  (setq loop T)
  (setq validTags (GetExampleTags "LEGENDA_JSJ_V1")) 
  (while loop
    (textscr)
    (princ "\n\n=== GESTOR GLOBAL ===")
    (foreach tName validTags (princ (strcat "\n • " tName)))
    (princ "\n-----------------------------------------")
    (setq selTag (strcase (getstring "\nDigite o NOME do Tag a alterar (ex: DATA): ")))
    
    (if (member selTag validTags)
      (progn
        (setq newVal (getstring T (strcat "\nNovo valor para '" selTag "' em TODOS os desenhos: ")))
        (ApplyGlobalValue "LEGENDA_JSJ_V1" selTag newVal)
      )
      (princ "\nTag inválido.")
    )
    (initget "Sim Nao")
    (setq continueLoop (getkword "\nAlterar outro campo global? [Sim/Nao] <Sim>: "))
    (if (= continueLoop "Nao") (setq loop nil))
  )
  (graphscr)
)

;; --- PROCESSO 3: MANUAL (A NOVA LÓGICA) ---
(defun ProcessManualReview ( / loop drawList i item userIdx selectedHandle field revLet dateVal descVal revVal attsToUpdate)
  (setq loop T)
  (while loop
    ;; 1. Listar Desenhos
    (setq drawList (GetDrawingList "LEGENDA_JSJ_V1"))
    (textscr)
    (princ "\n\n=== LISTA DE DESENHOS DISPONÍVEIS ===")
    (setq i 0)
    (foreach item drawList
      (princ (strcat "\n " (itoa (1+ i)) ". [Des: " (cadr item) "] - Layout: " (caddr item)))
      (setq i (1+ i))
    )
    (princ "\n-------------------------------------")
    
    ;; 2. Escolher Desenho
    (setq userIdx (getint (strcat "\nEscolha o número (1-" (itoa i) ") ou 0 para Sair: ")))
    
    (if (and userIdx (> userIdx 0) (<= userIdx i))
      (progn
        (setq selectedHandle (car (nth (1- userIdx) drawList)))
        
        ;; 3. Escolher Campo
        (initget "Tipo Titulo Revisao")
        (setq field (getkword "\nO que quer atualizar? [Tipo/Titulo/Revisao]: "))
        
        (cond
          ((= field "Tipo")
           (setq newVal (getstring T "\nNovo TIPO (ex: Betão Armado): "))
           (UpdateSingleTag selectedHandle "TIPO" newVal)
          )
          ((= field "Titulo")
           (setq newVal (getstring T "\nNovo TITULO: "))
           (UpdateSingleTag selectedHandle "TITULO" newVal)
          )
          ((= field "Revisao")
           (initget "A B C D E")
           (setq revLet (getkword "\nQual a Revisão? [A/B/C/D/E]: "))
           (if revLet
             (progn
               (princ (strcat "\n--- A editar Revisão " revLet " ---"))
               (setq dateVal (getstring T "\nData (ex: 2025-11-20): "))
               (setq descVal (getstring T "\nDescrição: "))
               (setq revVal (getstring T (strcat "\nLetra da Rev (Enter para '" revLet "'): ")))
               (if (= revVal "") (setq revVal revLet))
               
               ;; Atualiza os 3 campos
               (UpdateSingleTag selectedHandle (strcat "DATA_" revLet) dateVal)
               (UpdateSingleTag selectedHandle (strcat "DESC_" revLet) descVal)
               (UpdateSingleTag selectedHandle (strcat "REV_" revLet) revVal)
               (princ "\nRevisão atualizada com sucesso.")
             )
           )
          )
        )
      )
      (setq loop nil) ;; Sair se escolher 0
    )
    
    (if loop
      (progn
        (initget "Sim Nao")
        (if (= (getkword "\nRever outro desenho? [Sim/Nao] <Nao>: ") "Nao")
          (setq loop nil)
        )
      )
    )
  )
  (graphscr)
)

;; ============================================================================
;; FUNÇÕES AUXILIARES (CORE)
;; ============================================================================

;; Obtém lista: ((Handle "01" "Layout1") (Handle "02" "Layout2")...)
(defun GetDrawingList (blkName / doc listOut atts desNum)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq listOut '())
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
                 (= (strcase (vla-get-EffectiveName blk)) (strcase blkName)))
          (progn
            ;; Procura DES_NUM
            (setq desNum "??")
            (setq atts (vlax-invoke blk 'GetAttributes))
            (foreach att atts
              (if (= (strcase (vla-get-TagString att)) "DES_NUM")
                (setq desNum (vla-get-TextString att))
              )
            )
            ;; Adiciona à lista: (Handle Num LayoutName)
            ;; Usa append para manter ordem dos layouts se possivel, ou cons reverse
            (setq listOut (cons (list (vla-get-Handle blk) desNum (vla-get-Name lay)) listOut))
          )
        )
      )
    )
  )
  (reverse listOut) ;; Inverte para ficar na ordem de criação/layout
)

(defun UpdateSingleTag (handle tag val / ename obj atts tStr)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle))))
    (setq ename (handent handle))
  )
  (if (and ename (setq obj (vlax-ename->vla-object ename)))
    (progn
      (setq atts (vlax-invoke obj 'GetAttributes))
      (foreach att atts
        (setq tStr (strcase (vla-get-TagString att)))
        (if (= tStr (strcase tag))
          (vla-put-TextString att val)
        )
      )
      (vla-Update obj)
    )
  )
)

;; JSON Update Core
(defun UpdateBlockByHandle (handle pairList / ename obj atts tagVal foundVal)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle))))
    (setq ename (handent handle))
  )
  (if (and ename (setq obj (vlax-ename->vla-object ename)))
    (if (and (= (vla-get-ObjectName obj) "AcDbBlockReference")
             (= (vla-get-HasAttributes obj) :vlax-true))
      (progn
        (setq atts (vlax-invoke obj 'GetAttributes))
        (foreach att atts
          (setq tagVal (strcase (vla-get-TagString att)))
          (setq foundVal (cdr (assoc tagVal pairList)))
          (if foundVal (progn (vla-put-TextString att foundVal) (setq countUpdates (1+ countUpdates))))
        )
      )
    )
  )
)

(defun ApplyGlobalValue (blkName targetTag targetVal / doc atts tag)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
                 (= (strcase (vla-get-EffectiveName blk)) (strcase blkName)))
          (foreach att (vlax-invoke blk 'GetAttributes)
            (if (= (strcase (vla-get-TagString att)) targetTag)
              (vla-put-TextString att targetVal)
            )
          )
        )
      )
    )
  )
  (vla-Regen doc acActiveViewport)
)

(defun GetExampleTags (blkName / doc tagList found atts tag)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq tagList '() found nil)
  (vlax-for lay (vla-get-Layouts doc)
    (if (not found)
      (vlax-for blk (vla-get-Block lay)
        (if (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
                 (= (strcase (vla-get-EffectiveName blk)) (strcase blkName)))
          (progn
            (foreach att (vlax-invoke blk 'GetAttributes)
              (setq tag (strcase (vla-get-TagString att)))
              (if (and (/= tag "DES_NUM") (not (wcmatch tag "REV_?,DATA_?,DESC_?"))) 
                (setq tagList (cons tag tagList))
              )
            )
            (setq found T)
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
      (progn
        (setq nextChar (substr str (1+ i) 1))
        (cond ((= nextChar "\\") (setq result (strcat result "\\"))) ((= nextChar "\"") (setq result (strcat result "\""))) (t (setq result (strcat result char))))
        (setq i (1+ i)) 
      )
      (setq result (strcat result char))
    )
    (setq i (1+ i))
  )
  result
)