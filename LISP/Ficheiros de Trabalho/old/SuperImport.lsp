(defun c:SUPER_IMPORT ( / jsonFile fileDes line posSep handleVal attList doc obj inAttributes tag rawContent cleanContent countUpdates resp loop continueLoop validTags selTag newVal safeTagList)
  (vl-load-com)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq countUpdates 0)

  ;; ---------------------------------------------------------
  ;; PARTE 1: IMPORTAR O JSON (A BASE)
  ;; ---------------------------------------------------------
  (setq jsonFile (getfiled "Selecione o ficheiro JSON" "" "json" 4))
  
  (if (and jsonFile (findfile jsonFile))
    (progn
      (setq fileDes (open jsonFile "r"))
      (setq handleVal nil)
      (setq attList '())
      (setq inAttributes nil)

      (princ "\n[1/2] A processar JSON... ")

      (while (setq line (read-line fileDes))
        (setq line (vl-string-trim " \t" line))

        (cond
          ;; Encontra Handle
          ((vl-string-search "\"handle_bloco\":" line)
           (setq posSep (vl-string-search ":" line))
           (if posSep
             (progn
               (setq rawContent (substr line (+ posSep 2)))
               (setq handleVal (vl-string-trim " \"," rawContent))
               (setq attList '()) 
             )
           )
          )

          ;; Controla atributos
          ((vl-string-search "\"atributos\": {" line) (setq inAttributes T))
          ((and inAttributes (vl-string-search "}" line))
           (setq inAttributes nil)
           (if (and handleVal attList)
             (UpdateBlockByHandle handleVal attList)
           )
           (setq handleVal nil)
          )

          ;; Lê Tag: Valor
          (inAttributes
           (setq posSep (vl-string-search "\": \"" line))
           (if posSep
             (progn
               (setq tag (substr line 2 (- posSep 1)))
               (setq rawContent (substr line (+ posSep 5)))
               (setq cleanContent (vl-string-trim " \"," rawContent))
               (setq cleanContent (StringUnescape cleanContent))
               (setq attList (cons (cons (strcase tag) cleanContent) attList))
             )
           )
          )
        ) 
      ) 
      (close fileDes)
      (vla-Regen doc acActiveViewport)
      (princ (strcat "Concluído. (" (itoa countUpdates) " blocos atualizados via JSON)"))
    )
    (progn (princ "\nCancelado.") (exit))
  )

  ;; ---------------------------------------------------------
  ;; PARTE 2: GESTOR DE VARIÁVEIS GLOBAIS
  ;; ---------------------------------------------------------
  (princ "\n---------------------------------------------------------")
  (initget "Sim Nao")
  (setq resp (getkword "\n[2/2] Deseja definir variáveis GLOBAIS (iguais em todos os layouts)? [Sim/Nao] <Nao>: "))

  (if (= resp "Sim")
    (progn
      (setq loop T)
      ;; Obtém lista de tags válidos de um bloco qualquer (para dar opções ao user)
      (setq validTags (GetExampleTags "LEGENDA_JSJ_V1")) 

      (while loop
        (textscr) ;; Abre janela de texto para ver a lista melhor
        (princ "\n\n=== TAGS DISPONÍVEIS PARA EDIÇÃO GLOBAL ===")
        (princ "\n(Exclui automaticamente revisões e números de desenho)\n")
        
        ;; Imprime lista filtrada
        (foreach tName validTags
          (princ (strcat "\n • " tName))
        )
        
        (princ "\n\n-----------------------------------------")
        (setq selTag (strcase (getstring "\nDigite o NOME do Tag a alterar (ex: DATA): ")))

        ;; Validação simples: Verifica se o tag existe na lista (opcional, mas bom)
        (if (member selTag validTags)
          (progn
            (setq newVal (getstring T (strcat "\nNovo valor para '" selTag "' em TODOS os desenhos: ")))
            (princ "\nA aplicar... ")
            (ApplyGlobalValue "LEGENDA_JSJ_V1" selTag newVal)
          )
          (princ "\nERRO: Tag não encontrado ou protegido (revisão/desenho).")
        )

        ;; Pergunta se quer continuar
        (initget "Sim Nao")
        (setq continueLoop (getkword "\nDeseja alterar outro campo? [Sim/Nao] <Sim>: "))
        (if (= continueLoop "Nao") (setq loop nil))
      )
    )
  )
  
  (graphscr) ;; Fecha janela de texto
  (princ "\nProcesso Terminado com Sucesso!")
  (princ)
)

;; ---------------------------------------------------------
;; FUNÇÕES AUXILIARES
;; ---------------------------------------------------------

;; 1. Obtém lista de tags "Seguros" (Filtra DES_NUM e REVISÕES)
(defun GetExampleTags (blkName / doc layouts tagList found atts tag)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq tagList '())
  (setq found nil)
  
  ;; Procura o primeiro bloco que encontrar para ler a estrutura
  (vlax-for lay (vla-get-Layouts doc)
    (if (not found)
      (vlax-for blk (vla-get-Block lay)
        (if (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
                 (= (strcase (vla-get-EffectiveName blk)) (strcase blkName)))
          (progn
            (setq atts (vlax-invoke blk 'GetAttributes))
            (foreach att atts
              (setq tag (strcase (vla-get-TagString att)))
              
              ;; --- FILTRO DE PROTEÇÃO ---
              ;; Ignora DES_NUM
              ;; Ignora REV_?, DATA_?, DESC_? (onde ? é qualquer caracter simples, ex: A, B, 1)
              (if (and (/= tag "DES_NUM")
                       (not (wcmatch tag "REV_?,DATA_?,DESC_?"))) 
                (setq tagList (cons tag tagList))
              )
            )
            (setq found T)
          )
        )
      )
    )
  )
  (vl-sort tagList '<) ;; Retorna lista ordenada alfabeticamente
)

;; 2. Aplica valor a TODOS os blocos em TODOS os layouts
(defun ApplyGlobalValue (blkName targetTag targetVal / doc atts tag updateCount)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq updateCount 0)
  
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
                 (= (strcase (vla-get-EffectiveName blk)) (strcase blkName)))
          (progn
            (setq atts (vlax-invoke blk 'GetAttributes))
            (foreach att atts
              (setq tag (strcase (vla-get-TagString att)))
              (if (= tag targetTag)
                (progn
                  (vla-put-TextString att targetVal)
                  (setq updateCount (1+ updateCount))
                )
              )
            )
          )
        )
      )
    )
  )
  (vla-Regen doc acActiveViewport)
  (princ (strcat "Atualizado em " (itoa updateCount) " legendas.\n"))
)

;; 3. Atualiza Bloco Específico (JSON)
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
          (if foundVal 
             (progn
                (vla-put-TextString att foundVal)
                (setq countUpdates (1+ countUpdates)) ;; Incrementa contador global
             )
          )
        )
      )
    )
  )
)

;; 4. Limpeza de Escapes
(defun StringUnescape (str / result i char nextChar len)
  (setq result "")
  (setq len (strlen str))
  (setq i 1)
  (while (<= i len)
    (setq char (substr str i 1))
    (if (and (= char "\\") (< i len))
      (progn
        (setq nextChar (substr str (1+ i) 1))
        (cond
          ((= nextChar "\\") (setq result (strcat result "\\")))
          ((= nextChar "\"") (setq result (strcat result "\"")))
          (t (setq result (strcat result char))) 
        )
        (setq i (1+ i)) 
      )
      (setq result (strcat result char))
    )
    (setq i (1+ i))
  )
  result
)