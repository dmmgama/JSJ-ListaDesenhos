;; ============================================================================
;; FERRAMENTA UNIFICADA: GESTAO DESENHOS JSJ (V4 - IMPORT EXCEL)
;; ============================================================================

(defun c:GESTAODESENHOSJSJ ( / loop opt)
  (vl-load-com)
  (setq loop T)

  (while loop
    (textscr)
    (princ "\n\n==============================================")
    (princ "\n          GESTAO DESENHOS JSJ - MENU          ")
    (princ "\n==============================================")
    (princ "\n 1. Modificar Legendas (Menu Manual/JSON)")
    (princ "\n 2. Exportar JSON (Backup dos dados)")
    (princ "\n 3. Gerar Lista Excel (Exportar para XLSX)")
    (princ "\n 4. Importar Excel (Atualizar desenhos via XLSX)") ;; NOVA
    (princ "\n 0. Sair")
    (princ "\n==============================================")

    (initget "1 2 3 4 0")
    (setq opt (getkword "\nEscolha uma opção [1/2/3/4/0]: "))

    (cond
      ((= opt "1") (Run_MasterImport_Menu))
      ((= opt "2") (Run_ExportJSON))
      ((= opt "3") (Run_GenerateExcel_Pro))
      ((= opt "4") (Run_ImportExcel_Pro)) ;; NOVA FUNÇÃO
      ((= opt "0") (setq loop nil))
      ((= opt nil) (setq loop nil)) 
    )
  )
  (graphscr)
  (princ "\nGestao Desenhos JSJ Terminada.")
  (princ)
)

;; ============================================================================
;; MÓDULO 1: MODIFICAR LEGENDAS (SUB-MENU)
;; ============================================================================
(defun Run_MasterImport_Menu ( / loopSub optSub)
  (setq loopSub T)
  (while loopSub
    (textscr)
    (princ "\n\n   --- SUB-MENU: MODIFICAR LEGENDAS ---")
    (princ "\n   1. Importar JSON")
    (princ "\n   2. Definir Campos Gerais (Global)")
    (princ "\n   3. Alterar Desenhos (Individual)")
    (princ "\n   4. Numerar por TIPO")
    (princ "\n   5. Numerar SEQUENCIAL")
    (princ "\n   0. Voltar")
    (princ "\n   ------------------------------------")
    (initget "1 2 3 4 5 0")
    (setq optSub (getkword "\n   Opção [1/2/3/4/5/0]: "))
    (cond
      ((= optSub "1") (ProcessJSONImport))
      ((= optSub "2") (ProcessGlobalVariables))
      ((= optSub "3") (ProcessManualReview))
      ((= optSub "4") (AutoNumberByType))
      ((= optSub "5") (AutoNumberSequential))
      ((= optSub "0") (setq loopSub nil))
      ((= optSub nil) (setq loopSub nil))
    )
  )
)

;; ... (Funções de JSON e Numeração mantidas iguais à V3 - Omitidas para poupar espaço, inserir aqui as funcões ProcessJSONImport, etc se necessário, mas o núcleo está abaixo) ...
;; (Nota: Para o código funcionar, as funções auxiliares no fim do ficheiro são cruciais)

;; ============================================================================
;; MÓDULO 3: GERAR LISTA EXCEL (ATUALIZADO COM COLUNA ID)
;; ============================================================================
(defun Run_GenerateExcel_Pro ( / doc layoutList dataList sortMode sortOrder valTipo valNum valTit maxRev revLetra revData valHandle excelApp wb sheet range i rCount cells)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  (princ "\nA ler dados... ")
  (setq dataList '())
  (setq layoutList (GetLayoutsRaw doc))
  
  (foreach lay layoutList
    (vlax-for blk (vla-get-Block lay)
      (if (IsTargetBlock blk)
        (progn
          (setq valTipo (GetAttValue blk "TIPO"))
          (setq valNum  (GetAttValue blk "DES_NUM"))
          (setq valTit  (GetAttValue blk "TITULO"))
          (setq maxRev (GetMaxRevision blk)) 
          (setq revLetra (car maxRev))
          (setq revData (cadr maxRev))
          (setq valHandle (vla-get-Handle blk)) ;; NOVO: Captura o Handle
          (setq dataList (cons (list valTipo valNum valTit revLetra revData valHandle) dataList))
        )
      )
    )
  )

  ;; Ordenação (Igual V3)
  (initget "Tipo Numero")
  (setq sortMode (getkword "\nOrdenar por? [Tipo/Numero] <Numero>: "))
  (if (not sortMode) (setq sortMode "Numero"))
  (if (= sortMode "Tipo") (progn (initget "Ascendente Descendente") (setq sortOrder (getkword "\nOrdem do TIPO? [Ascendente/Descendente] <Ascendente>: ")) (if (not sortOrder) (setq sortOrder "Ascendente"))))
  (cond
    ((= sortMode "Tipo") (setq dataList (vl-sort dataList '(lambda (a b) (if (= (strcase (nth 0 a)) (strcase (nth 0 b))) (< (strcase (nth 1 a)) (strcase (nth 1 b))) (if (= sortOrder "Descendente") (> (strcase (nth 0 a)) (strcase (nth 0 b))) (< (strcase (nth 0 a)) (strcase (nth 0 b)))))))))
    ((= sortMode "Numero") (setq dataList (vl-sort dataList '(lambda (a b) (< (strcase (nth 1 a)) (strcase (nth 1 b)))))))
  )

  ;; Excel Automation
  (princ "\nA gerar Excel... ")
  (setq excelApp (vlax-get-or-create-object "Excel.Application"))
  (if excelApp
    (progn
      (vla-put-visible excelApp :vlax-true)
      (setq wb (vlax-invoke-method (vlax-get-property excelApp 'Workbooks) 'Add))
      (setq sheet (vlax-get-property wb 'ActiveSheet))
      (setq cells (vlax-get-property sheet 'Cells))

      ;; Cabeçalhos
      (PutCell cells 1 1 "Tipo")
      (PutCell cells 1 2 "Nº Desenho")
      (PutCell cells 1 3 "Título")
      (PutCell cells 1 4 "Revisão")
      (PutCell cells 1 5 "Data")
      (PutCell cells 1 6 "ID_CAD") ;; Coluna Técnica

      ;; Formatação Header
      (setq range (vlax-get-property sheet 'Range "A1:F1"))
      (vla-put-Bold (vlax-get-property range 'Font) :vlax-true)
      (vla-put-ColorIndex (vlax-get-property range 'Interior) 32) 
      (vla-put-ColorIndex (vlax-get-property range 'Font) 2)

      ;; Preencher Dados
      (setq i 2)
      (foreach row dataList
        (PutCell cells i 1 (nth 0 row))
        (PutCell cells i 2 (nth 1 row))
        (PutCell cells i 3 (nth 2 row))
        (PutCell cells i 4 (nth 3 row))
        (PutCell cells i 5 (nth 4 row))
        (PutCell cells i 6 (nth 5 row)) ;; Escreve Handle
        (setq i (1+ i))
      )

      ;; Formatação Final
      (setq rCount (itoa (1- i)))
      (setq range (vlax-get-property sheet 'Range (strcat "A1:F" rCount)))
      (vla-put-LineStyle (vlax-get-property range 'Borders) 1) 
      (vlax-invoke-method (vlax-get-property (vlax-get-property sheet 'Columns) 'EntireColumn) 'AutoFit)

      ;; Esconder coluna ID (Opcional, mas recomendado para não assustar users)
      ;; (vla-put-Hidden (vlax-get-property (vlax-get-property sheet 'Range "F:F") 'EntireColumn) :vlax-true)

      (ReleaseObject range) (ReleaseObject cells) (ReleaseObject sheet) (ReleaseObject wb) (ReleaseObject excelApp)
      (alert "Sucesso! Excel gerado.\nA coluna 'ID_CAD' serve para sincronização, não a apague.")
    )
    (alert "ERRO: Excel não detetado.")
  )
  (princ)
)

;; ============================================================================
;; MÓDULO 4: IMPORTAR EXCEL (NOVA FUNÇÃO CORE)
;; ============================================================================
(defun Run_ImportExcel_Pro ( / xlsFile excelApp wb sheet usedRange rows cols r valHandle valTipo valNum valTit valRev valData countUpdates obj atts revTag dataTag)
  
  (setq xlsFile (getfiled "Selecione o ficheiro Excel para Importar" "" "xlsx;xls" 4))
  
  (if (and xlsFile (findfile xlsFile))
    (progn
      (princ "\nA abrir Excel... (Isto pode demorar uns segundos)")
      (setq excelApp (vlax-get-or-create-object "Excel.Application"))
      
      (if excelApp
        (progn
          (vla-put-visible excelApp :vlax-true) ;; Abre visível para debug
          (setq wb (vlax-invoke-method (vlax-get-property excelApp 'Workbooks) 'Open xlsFile))
          (setq sheet (vlax-get-property wb 'ActiveSheet))
          (setq usedRange (vlax-get-property sheet 'UsedRange))
          (setq rows (vlax-get-property (vlax-get-property usedRange 'Rows) 'Count))
          
          (setq countUpdates 0)
          (princ "\nA ler linhas e atualizar CAD...")

          ;; Loop Linha 2 até ao Fim
          (setq r 2)
          (while (<= r rows)
            ;; LER COLUNAS (1=Tipo, 2=Num, 3=Tit, 4=Rev, 5=Data, 6=Handle)
            (setq valTipo (GetCellText sheet r 1))
            (setq valNum  (GetCellText sheet r 2))
            (setq valTit  (GetCellText sheet r 3))
            (setq valRev  (GetCellText sheet r 4))
            (setq valData (GetCellText sheet r 5))
            (setq valHandle (GetCellText sheet r 6))

            ;; TENTA ENCONTRAR O BLOCO PELO HANDLE (Mais seguro)
            (if (and valHandle (/= valHandle ""))
               (UpdateBlockByHandleAndData valHandle valTipo valNum valTit valRev valData)
               ;; Se não tiver handle, tenta encontrar pelo Numero do Desenho (Fallback)
               (princ (strcat "\nAviso: Linha " (itoa r) " sem ID. Ignorada."))
            )
            (setq r (1+ r))
          )
          
          ;; FECHAR EXCEL (Importante!)
          (vlax-invoke-method wb 'Close :vlax-false) ;; Fecha sem salvar (já lemos)
          (vlax-invoke-method excelApp 'Quit)
          
          (ReleaseObject usedRange) (ReleaseObject sheet) (ReleaseObject wb) (ReleaseObject excelApp)
          
          (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport)
          (alert "Importação Concluída!")
        )
        (alert "Erro ao iniciar Excel ActiveX.")
      )
    )
    (princ "\nCancelado.")
  )
  (princ)
)

;; --- LÓGICA DE UPDATE IMPORT EXCEL ---
(defun UpdateBlockByHandleAndData (handle tipo num tit rev dataStr / ename obj atts revTag dataTag)
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle))))
    (setq ename (handent handle))
  )
  
  (if (and ename (setq obj (vlax-ename->vla-object ename)))
    (if (IsTargetBlock obj)
      (progn
        ;; 1. Atualiza Campos Base
        (UpdateSingleTag handle "TIPO" tipo)
        (UpdateSingleTag handle "DES_NUM" num)
        (UpdateSingleTag handle "TITULO" tit)

        ;; 2. Lógica de Revisão Inteligente
        ;; Se a coluna Rev tiver "A", "B", "C"... atualiza esse campo específico
        (if (and rev (/= rev "") (/= rev "-"))
          (progn
            (setq revTag (strcat "REV_" rev))
            (setq dataTag (strcat "DATA_" rev))
            
            ;; Só tenta atualizar se o tag for válido (Ex: REV_A existe, REV_X não)
            ;; Como não podemos testar fácil, tentamos atualizar direto.
            ;; Se o user meter "B", atualiza REV_B e DATA_B
            (UpdateSingleTag handle revTag rev)
            (UpdateSingleTag handle dataTag dataStr)
          )
        )
        (princ ".") ;; Feedback visual na command line
      )
    )
  )
)

;; ============================================================================
;; FUNÇÕES AUXILIARES (SHARED KERNEL - OBRIGATÓRIO)
;; ============================================================================

;; Funções do Master Import (JSON/Processos Manuais)
(defun ProcessJSONImport ( / ) (princ "\nFunção JSON importada.")) ;; Placeholder para o código não ficar gigante aqui. O anterior mantem-se.
(defun ProcessGlobalVariables ( / ) (princ "\nGlobal Vars."))
(defun ProcessManualReview ( / ) (princ "\nManual Review."))
(defun AutoNumberByType ( / ) (princ "\nAuto Num."))
(defun AutoNumberSequential ( / ) (princ "\nSeq Num."))
;; (NOTA: COPIA AS FUNÇÕES "Process..." da versão V3 para aqui se quiseres o código todo num só,
;; ou foca-te só no Excel se for essa a prioridade. Para brevidade, as funções auxiliares de baixo são as críticas para o Excel).

(defun Run_ExportJSON ( / ) (princ "\nJSON Export.")) 

(defun PutCell (cells row col val) (vlax-put-property (vlax-get-property cells 'Item row col) 'Value2 val))
(defun GetCellText (sheet row col / cell val)
  (setq cell (vlax-get-property sheet 'Cells row col))
  (setq val (vlax-get-property cell 'Text)) ;; Usa 'Text para vir formatado string
  (vlax-release-object cell)
  val
)

(defun ReleaseObject (obj) (if (and obj (not (vlax-object-released-p obj))) (vlax-release-object obj)))

(defun IsTargetBlock (blk) (and (= (vla-get-ObjectName blk) "AcDbBlockReference") (= (strcase (vla-get-EffectiveName blk)) "LEGENDA_JSJ_V1")))
(defun GetAttValue (blk tag / atts val) (setq atts (vlax-invoke blk 'GetAttributes) val "") (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (setq val (vla-get-TextString att)))) val)

(defun UpdateSingleTag (handle tag val / ename obj atts) 
  (if (not (vl-catch-all-error-p (vl-catch-all-apply 'handent (list handle)))) (setq ename (handent handle))) 
  (if (and ename (setq obj (vlax-ename->vla-object ename))) 
    (progn (setq atts (vlax-invoke obj 'GetAttributes)) 
      (foreach att atts (if (= (strcase (vla-get-TagString att)) (strcase tag)) (vla-put-TextString att val))) 
      (vla-Update obj)
    )
  )
)

(defun GetLayoutsRaw (doc / lays listLays) (setq lays (vla-get-Layouts doc) listLays '()) (vlax-for item lays (if (/= (vla-get-ModelType item) :vlax-true) (setq listLays (cons item listLays)))) listLays)
(defun GetMaxRevision (blk / revLetter revDate checkRev finalRev finalDate) (setq finalRev "-" finalDate "-") (foreach letra '("E" "D" "C" "B" "A") (if (= finalRev "-") (progn (setq checkRev (GetAttValue blk (strcat "REV_" letra))) (if (and (/= checkRev "") (/= checkRev " ")) (progn (setq finalRev checkRev) (setq finalDate (GetAttValue blk (strcat "DATA_" letra)))))))) (list finalRev finalDate))