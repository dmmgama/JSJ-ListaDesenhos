;; ============================================================================
;; MIGRAR LEGENDAS ANTIGAS PARA LEGENDA_JSJ_V1 (V2)
;; Atualização: Mantém a posição exata (X,Y) da legenda antiga.
;; ============================================================================

(defun c:MIGRAR_LEGENDAS_JSJ ( / doc layouts blkName xrefName textLayer globalVals tagsToAsk tag val count pSpace newBlk insPoint foundXref)
  (vl-load-com)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq layouts (vla-get-Layouts doc))
  (setq blkName "LEGENDA_JSJ_V1")

  ;; 1. VERIFICAR SE O BLOCO ALVO EXISTE
  (if (vl-catch-all-error-p (vl-catch-all-apply 'vla-Item (list (vla-get-Blocks doc) blkName)))
    (progn
      (alert (strcat "ERRO CRÍTICO:\nO bloco '" blkName "' não existe neste desenho.\nInsira-o uma vez e tente novamente."))
      (exit)
    )
  )

  (textscr)
  (princ "\n==============================================")
  (princ "\n   MIGRAÇÃO DE LEGENDAS V2 (Mesma Posição)    ")
  (princ "\n==============================================")

  ;; 2. CONFIGURAR LIMPEZA
  (setq xrefName (getstring T "\nNome do XREF antigo a substituir (ex: A1_BASE): "))
  (setq textLayer (getstring T "\nNome do LAYER do texto antigo a apagar (ex: LEGENDAS): "))

  ;; 3. RECOLHER DADOS GERAIS
  (princ "\n\n--- DADOS GERAIS ---")
  (setq tagsToAsk '("CLIENTE" "OBRA" "LOCALIZACAO" "ESPECIALIDADE" "FASE" "DATA" "ESCALAS" "PROJECTOU"))
  (setq globalVals '())

  (foreach tag tagsToAsk
    (setq val (getstring T (strcat "\nValor para '" tag "': ")))
    (if (/= val "")
      (setq globalVals (cons (cons tag val) globalVals))
    )
  )

  ;; 4. EXECUTAR A MIGRAÇÃO
  (princ "\n\n--- A PROCESSAR ---")
  (setq count 0)

  (vlax-for lay layouts
    (if (/= (vla-get-ModelType lay) :vlax-true) ;; Ignora ModelSpace
      (progn
        (princ (strcat "\nLayout: " (vla-get-Name lay) "... "))
        (setq pSpace (vla-get-Block lay))
        (setq insPoint (vlax-3d-point 0 0 0)) ;; Ponto base (caso não ache o xref)
        (setq foundXref nil)

        ;; A. PROCURAR XREF, GUARDAR POSIÇÃO E APAGAR
        (vlax-for obj pSpace
          ;; Verifica se é o Xref alvo
          (if (and (= (vla-get-ObjectName obj) "AcDbBlockReference")
                   (= (strcase (vla-get-Name obj)) (strcase xrefName)))
             (progn
               ;; *** O SEGREDO ESTÁ AQUI ***
               ;; Guarda o ponto de inserção do Xref antes de o apagar
               (setq insPoint (vla-get-InsertionPoint obj))
               (setq foundXref T)
               (vla-Delete obj)
             )
          )
          ;; Apaga Textos do layer indicado
          (if (and (or (= (vla-get-ObjectName obj) "AcDbText") (= (vla-get-ObjectName obj) "AcDbMText"))
                   (= (strcase (vla-get-Layer obj)) (strcase textLayer)))
             (vla-Delete obj)
          )
        )

        ;; B. INSERIR NOVA LEGENDA
        ;; Se encontrou o Xref, usa o ponto dele. Se não, usa 0,0,0.
        (if foundXref
            (princ "Xref substituído. ")
            (princ "Xref não encontrado (inserido na origem). ")
        )

        (setq newBlk (vla-InsertBlock pSpace insPoint blkName 1 1 1 0))
        
        ;; C. PREENCHER ATRIBUTOS
        (if (= (vla-get-HasAttributes newBlk) :vlax-true)
          (foreach att (vlax-invoke newBlk 'GetAttributes)
            (setq tag (strcase (vla-get-TagString att)))
            (setq val (cdr (assoc tag globalVals)))
            (if val (vla-put-TextString att val))
          )
        )
        (setq count (1+ count))
      )
    )
  )

  (vla-Regen doc acActiveViewport)
  (alert (strcat "Concluído!\nAtualizados " (itoa count) " layouts.\nAs legendas mantiveram a posição dos Xrefs originais."))
  (princ)
)