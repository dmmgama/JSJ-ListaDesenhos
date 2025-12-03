;; ============================================================================
;; EXTRATOR_LEGENDA_JSJ.lsp
;; Extrai atributos de blocos LEGENDA_JSJ_V1 e gera JSON para jsj_app.py
;; Versão: 1.0
;; Autor: JSJ
;; Data: 2025-11-20
;; ============================================================================

(defun C:EXTRAIR_JSJ (/ layouts resultado ss i ent blk-name attribs-list json-output file)
  (princ "\n=== EXTRATOR DE LEGENDAS JSJ ===\n")
  
  (setq resultado '())  ; Lista para armazenar todos os desenhos extraídos
  
  ;; Iterar todos os layouts (Paper Space)
  (vlax-for layout (vla-get-Layouts (vla-get-ActiveDocument (vlax-get-acad-object)))
    (setq layout-name (vla-get-Name layout))
    
    ;; Ignorar Model Space
    (if (/= layout-name "Model")
      (progn
        (princ (strcat "\nA processar layout: " layout-name))
        
        ;; Mudar para o layout
        (setvar "CTAB" layout-name)
        
        ;; Selecionar todos os blocos LEGENDA no layout atual
        (setq ss (ssget "X" (list 
          (cons 0 "INSERT")
          (cons 2 "LEGENDA_JSJ_V1")
          (cons 410 layout-name)
        )))
        
        (if ss
          (progn
            (setq i 0)
            (repeat (sslength ss)
              (setq ent (ssname ss i))
              (setq blk-name (cdr (assoc 2 (entget ent))))
              
              ;; Extrair atributos do bloco
              (setq attribs-list (extrair-atributos ent))
              
              ;; Adicionar metadados
              (setq attribs-list (append attribs-list
                (list
                  (cons "LAYOUT" layout-name)
                  (cons "BLOCO_NUM" (1+ i))
                )))
              
              ;; Adicionar à lista de resultados
              (setq resultado (append resultado (list attribs-list)))
              
              (princ (strcat "\n  Bloco " (itoa (1+ i)) ": " 
                (cdr (assoc "DES_NUM" attribs-list))))
              
              (setq i (1+ i))
            )
            (princ (strcat "\n  Total: " (itoa (sslength ss)) " blocos LEGENDA encontrados"))
          )
          (princ "\n  Nenhum bloco LEGENDA encontrado")
        )
      )
    )
  )
  
  ;; Gerar JSON
  (if resultado
    (progn
      (setq json-output (gerar-json resultado))
      
      ;; Guardar ficheiro
      (setq file (open (strcat (getvar "DWGPREFIX") (getvar "DWGNAME") ".jsj.json") "w"))
      (princ json-output file)
      (close file)
      
      (princ (strcat "\n\n=== EXTRACAO COMPLETA ==="))
      (princ (strcat "\nTotal de desenhos: " (itoa (length resultado))))
      (princ (strcat "\nFicheiro gerado: " (getvar "DWGNAME") ".jsj.json"))
      (princ "\n\nCarrega este ficheiro na app JSJ Parser!")
    )
    (princ "\n\nNenhum bloco LEGENDA encontrado no desenho.")
  )
  
  (princ)
)

;; ============================================================================
;; FUNCAO: extrair-atributos
;; Extrai todos os atributos de um bloco INSERT
;; ============================================================================
(defun extrair-atributos (ent / attribs obj att-name att-value result)
  (setq result '())
  (setq obj (vlax-ename->vla-object ent))
  
  (if (= (vla-get-HasAttributes obj) :vlax-true)
    (progn
      (setq attribs (vlax-invoke obj 'GetAttributes))
      (foreach att (vlax-safearray->list (vlax-variant-value attribs))
        (setq att-name (vla-get-TagString att))
        (setq att-value (vla-get-TextString att))
        (setq result (append result (list (cons att-name att-value))))
      )
    )
  )
  result
)

;; ============================================================================
;; FUNCAO: gerar-json
;; Converte lista de associação para formato JSON
;; ============================================================================
(defun gerar-json (data / output)
  (setq output "{\n  \"desenhos\": [\n")
  
  ;; Iterar cada desenho
  (setq first-item T)
  (foreach desenho data
    (if (not first-item)
      (setq output (strcat output ",\n"))
    )
    (setq first-item nil)
    
    (setq output (strcat output "    {\n"))
    
    ;; Adicionar cada campo
    (setq first-field T)
    (foreach campo desenho
      (if (not first-field)
        (setq output (strcat output ",\n"))
      )
      (setq first-field nil)
      
      (setq output (strcat output 
        "      \"" (car campo) "\": \"" 
        (escapar-json (cdr campo)) "\""))
    )
    
    (setq output (strcat output "\n    }"))
  )
  
  (setq output (strcat output "\n  ],\n"))
  
  ;; Metadados
  (setq output (strcat output 
    "  \"metadata\": {\n"
    "    \"total_desenhos\": " (itoa (length data)) ",\n"
    "    \"dwg_file\": \"" (getvar "DWGNAME") "\",\n"
    "    \"extraction_date\": \"" (menucmd "M=$(edtime,$(getvar,date),DD/MM/YYYY)") "\",\n"
    "    \"extractor_version\": \"1.0\"\n"
    "  }\n"
    "}\n"))
  
  output
)

;; ============================================================================
;; FUNCAO: escapar-json
;; Escapa caracteres especiais para JSON
;; ============================================================================
(defun escapar-json (str / result)
  (setq result str)
  (setq result (vl-string-subst "\\\\" "\\" result))
  (setq result (vl-string-subst "\\\"" "\"" result))
  (setq result (vl-string-subst "\\n" "\n" result))
  result
)

;; ============================================================================
;; COMANDO SIMPLIFICADO
;; ============================================================================
(defun C:JSJ () (C:EXTRAIR_JSJ))

(princ "\n=== EXTRATOR JSJ CARREGADO ===")
(princ "\nComandos disponiveis:")
(princ "\n  EXTRAIR_JSJ ou JSJ - Extrai legendas e gera JSON")
(princ "\n================================\n")
(princ)