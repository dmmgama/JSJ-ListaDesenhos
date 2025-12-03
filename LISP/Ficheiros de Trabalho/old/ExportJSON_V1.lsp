(defun c:GET_JSON ( / doc path name jsonFile fileDes layouts blkName targetBlockName jsonList jsonItem atts idVal handleVal subList tag val escapedVal)
  (vl-load-com)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  ;; --- CONFIGURAÇÃO ---
  ;; Coloca aqui o nome do bloco. A lisp fará a comparação insensível a maiúsculas/minúsculas.
  (setq targetBlockName "LEGENDA_JSJ_V1") 

  ;; 1. VERIFICA SE O DESENHO ESTÁ SALVO
  (setq path (vla-get-Path doc))
  (if (= path "")
    (progn 
      (alert "Erro: O desenho precisa de ser salvo no disco primeiro!")
      (exit)
    )
  )

  (setq name (vl-filename-base (vla-get-Name doc)))
  (setq jsonFile (strcat path "\\" name "_legendas.json"))
  (setq jsonList '()) 

  ;; --- FUNÇÃO AUXILIAR: ESCAPAR CARACTERES PROIBIDOS NO JSON ---
  (defun EscapeJSON (str / i char result len)
    (setq result "")
    (setq len (strlen str))
    (setq i 1)
    (while (<= i len)
      (setq char (substr str i 1))
      (cond
        ((= char "\\") (setq result (strcat result "\\\\"))) 
        ((= char "\"") (setq result (strcat result "\\\""))) 
        (t (setq result (strcat result char)))
      )
      (setq i (1+ i))
    )
    result
  )

  ;; --- 2. ITERAR LAYOUTS ---
  (vlax-for layout (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType layout) :vlax-true) ;; Ignora ModelSpace
      (vlax-for blk (vla-get-Block layout)
        
        ;; VERIFICAÇÃO DE NOME (Robustez para Blocos Dinâmicos)
        ;; Compara o EffectiveName em maiúsculas com o Alvo em maiúsculas
        (if (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
                 (= (strcase (vla-get-EffectiveName blk)) (strcase targetBlockName)))
          (progn
            (setq handleVal (vla-get-Handle blk))
            (setq atts (vlax-invoke blk 'GetAttributes))
            (setq subList "")
            (setq idVal "") 

            ;; --- 3. EXTRAIR E LIMPAR ATRIBUTOS ---
            (foreach att atts
              (setq tag (vla-get-TagString att))
              (setq val (vla-get-TextString att))
              
              (setq escapedVal (EscapeJSON val))

              ;; Captura o ID se for o tag DES_NUM
              (if (= (strcase tag) "DES_NUM") (setq idVal escapedVal))

              ;; Constrói par "TAG": "VALOR"
              (setq subList (strcat subList "      \"" tag "\": \"" escapedVal "\",\n"))
            )

            ;; Remove a última vírgula
            (if (> (strlen subList) 2)
              (setq subList (substr subList 1 (- (strlen subList) 2)))
            )

            ;; Fallback de ID se DES_NUM estiver vazio
            (if (= idVal "") (setq idVal (strcat "ND_" handleVal)))

            ;; --- 4. MONTAR O OBJETO JSON ---
            (setq jsonItem (strcat 
              "  {\n"
              "    \"id_desenho\": \"" idVal "\",\n"
              "    \"layout_tab\": \"" (vla-get-Name layout) "\",\n"
              "    \"handle_bloco\": \"" handleVal "\",\n"
              "    \"atributos\": {\n" subList "\n    }\n"
              "  }"
            ))
            
            (setq jsonList (cons jsonItem jsonList))
          )
        )
      )
    )
  )

  ;; --- 5. ESCREVER FICHEIRO FINAL ---
  (if jsonList
    (progn
      (setq fileDes (open jsonFile "w"))
      (write-line "[" fileDes)
      
      (setq i 0)
      (foreach item (reverse jsonList) 
        (if (> i 0) (write-line "," fileDes)) 
        (princ item fileDes)
        (setq i (1+ i))
      )
      
      (write-line "\n]" fileDes)
      (close fileDes)
      (alert (strcat "Sucesso!\nFicheiro criado em:\n" jsonFile))
    )
    (alert (strcat "Aviso: Bloco '" targetBlockName "' não encontrado em nenhum Layout."))
  )
  (princ)
)