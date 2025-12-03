(defun c:SET_JSON ( / jsonFile fileDes line posSep handleVal attList doc obj inAttributes tag rawContent cleanContent countUpdates)
  (vl-load-com)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))

  ;; --- 1. SELEÇÃO DO FICHEIRO ---
  (setq jsonFile (getfiled "Selecione o ficheiro JSON" "" "json" 4))
  
  (if (and jsonFile (findfile jsonFile))
    (progn
      (setq fileDes (open jsonFile "r"))
      (setq handleVal nil)
      (setq attList '())
      (setq inAttributes nil)
      (setq countUpdates 0)

      (princ "\nA processar JSON... Aguarde.")

      ;; --- 2. LEITURA LINHA A LINHA ---
      (while (setq line (read-line fileDes))
        ;; Limpeza básica de espaços nas pontas da linha completa
        (setq line (vl-string-trim " \t" line))

        (cond
          ;; CASO A: Encontra o Handle do Bloco (Lógica simplificada)
          ((vl-string-search "\"handle_bloco\":" line)
           (setq posSep (vl-string-search ":" line))
           (if posSep
             (progn
               (setq rawContent (substr line (+ posSep 2))) ;; Pega o que está depois dos dois pontos
               (setq handleVal (vl-string-trim " \"," rawContent)) ;; Limpa aspas e virgulas do ID
               (setq attList '()) 
             )
           )
          )

          ;; CASO B: Controla entrada/saida dos atributos
          ((vl-string-search "\"atributos\": {" line) (setq inAttributes T))
          ((and inAttributes (vl-string-search "}" line))
           (setq inAttributes nil)
           ;; EXECUTA O UPDATE
           (if (and handleVal attList)
             (UpdateBlockByHandle handleVal attList)
           )
           (setq handleVal nil)
          )

          ;; CASO C: Processa a linha "TAG": "VALOR"
          (inAttributes
           (setq posSep (vl-string-search "\": \"" line))
           (if posSep
             (progn
               ;; 1. Isola a TAG (Esquerda do separador)
               ;; O separador começa no indice posSep. A tag vai do inicio até lá.
               (setq tag (substr line 2 (- posSep 1))) ;; O "2" salta a primeira aspa
               
               ;; 2. Isola o CONTEUDO (Direita do separador)
               ;; posSep é o indice da primeira aspa do separador `": "`.
               ;; O separador tem 4 caracteres. Somamos 5 para garantir que pegamos o texto à frente.
               (setq rawContent (substr line (+ posSep 5)))
               
               ;; 3. LIMPEZA CRÍTICA (A CORREÇÃO)
               ;; Remove Espaços, Aspas e Vírgulas das extremidades da string
               (setq cleanContent (vl-string-trim " \"," rawContent))
               
               ;; 4. Remove Escapes (\") se existirem
               (setq cleanContent (StringUnescape cleanContent))
               
               ;; Adiciona à lista
               (setq attList (cons (cons (strcase tag) cleanContent) attList))
             )
           )
          )
        ) 
      ) 
      
      (close fileDes)
      (vla-Regen doc acActiveViewport)
      (alert (strcat "Sucesso!\nBlocos atualizados: " (itoa countUpdates)))
    )
    (princ "\nCancelado.")
  )
  (princ)
)

;; --- ATUALIZA O BLOCO ---
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
          
          ;; Se encontrar valor no JSON, atualiza.
          (if foundVal (vla-put-TextString att foundVal))
        )
        (setq countUpdates (1+ countUpdates))
      )
    )
  )
)

;; --- LIMPEZA DE ESCAPES ---
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