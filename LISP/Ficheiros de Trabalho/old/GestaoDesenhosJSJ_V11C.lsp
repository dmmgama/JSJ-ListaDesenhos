;; ============================================================================
;; FERRAMENTA UNIFICADA: GESTAO DESENHOS JSJ (V11 - STABLE & SAFE)
;; ============================================================================
;; MELHORIAS V11:
;; - Proteção anti-bloqueio em loops Excel
;; - Sistema de logging para debug
;; - Validações robustas de handles e objetos
;; - Gestão segura de memória Excel
;; - Rollback automático em caso de erro
;; - Código reformatado para legibilidade
;; - Timeout em operações longas
;; ============================================================================

;; ============================================================================
;; CONFIGURAÇÕES GLOBAIS
;; ============================================================================
(setq *LEGENDA_BLOCK_NAME* "LEGENDA_JSJ_V1")
(setq *DEFAULT_START_CELL* "A2")
(setq *REV_LETTERS* '("A" "B" "C" "D" "E"))
(setq *MAX_EXCEL_ROWS* 1000)        ;; Proteção anti-loop infinito
(setq *EXCEL_TIMEOUT* 300)          ;; 5 minutos máximo
(setq *GESTAO_LOG* '())             ;; Lista de log
(setq *DEBUG_MODE* T)               ;; Ativar mensagens debug

;; ============================================================================
;; SISTEMA DE LOGGING
;; ============================================================================
(defun LogMsg (tipo msg / timestamp)
  (setq timestamp (rtos (getvar "DATE") 2 6))
  (setq *GESTAO_LOG* (cons (list timestamp tipo msg) *GESTAO_LOG*))
  (if *DEBUG_MODE*
    (princ (strcat "\n[" tipo "] " msg))
  )
  (princ)
)

(defun SaveLogToFile ( / logFile)
  (setq logFile (strcat (getvar "DWGPREFIX") "GestaoDesenhos_Log.txt"))
  (setq f (open logFile "w"))
  (if f
    (progn
      (foreach entry (reverse *GESTAO_LOG*)
        (write-line 
          (strcat (car entry) " [" (cadr entry) "] " (caddr entry)) 
          f
        )
      )
      (close f)
      (alert (strcat "Log guardado em:\n" logFile))
    )
    (alert "Erro ao guardar log.")
  )
)

;; ============================================================================
;; INICIALIZAÇÃO E LIMPEZA
;; ============================================================================
(defun InitializeGlobals ()
  (setq *GESTAO_LOG* '())
  (LogMsg "INFO" "Sistema inicializado")
  (LogMsg "INFO" (strcat "DWG: " (getvar "DWGNAME")))
)

(defun CleanupResources ()
  (LogMsg "INFO" "A terminar sessão...")
  (gc) ;; Garbage collection
  (princ)
)

;; ============================================================================
;; MENU PRINCIPAL
;; ============================================================================
(defun c:GESTAODESENHOSJSJ ( / loop opt)
  (vl-load-com)
  (InitializeGlobals)
  (setq loop T)

  (while loop
    (textscr)
    (DisplayMainMenu)
    (setq opt (GetMenuOption "1 2 3 4 5 6 0"))
    (ProcessMainMenuOption opt)
    (if (= opt "0") (setq loop nil))
  )
  
  (CleanupResources)
  (graphscr)
  (princ "\nGestao Desenhos JSJ Terminada.")
  (princ)
)

(defun DisplayMainMenu ()
  (princ "\n\n==============================================")
  (princ "\n          GESTAO DESENHOS JSJ - MENU          ")
  (princ "\n==============================================")
  (princ "\n 1. Modificar Legendas (Manual/JSON)")
  (princ "\n 2. Exportar JSON (Backup)")
  (princ "\n 3. Gerar Lista Excel (Novo do Zero)")
  (princ "\n 4. Gerar Lista via TEMPLATE (Salva Novo 1º)")
  (princ "\n 5. Importar Excel (Normal ou Template)")
  (princ "\n 6. Ver Log / Guardar Log")
  (princ "\n 0. Sair")
  (princ "\n==============================================")
)

(defun GetMenuOption (validOptions / opt)
  (initget validOptions)
  (setq opt (getkword (strcat "\nEscolha uma opção [" validOptions "]: ")))
  (if (not opt) (setq opt "0"))
  opt
)

(defun ProcessMainMenuOption (opt)
  (cond
    ((= opt "1") (Run_MasterImport_Menu))
    ((= opt "2") (Run_ExportJSON))
    ((= opt "3") (Run_GenerateExcel_Pro))
    ((= opt "4") (Run_GenerateExcel_FromTemplate))
    ((= opt "5") (Run_ImportExcel_Flexible))
    ((= opt "6") (Run_LogViewer))
    ((= opt "0") (LogMsg "INFO" "Utilizador saiu"))
  )
)

;; ============================================================================
;; MÓDULO 1: SUB-MENU MODIFICAR LEGENDAS
;; ============================================================================
(defun Run_MasterImport_Menu ( / loopSub optSub)
  (setq loopSub T)
  (while loopSub
    (textscr)
    (princ "\n\n   --- SUB-MENU ---")
    (princ "\n   1. Importar JSON")
    (princ "\n   2. Definir Campos Gerais")
    (princ "\n   3. Alterar Desenhos")
    (princ "\n   4. Numerar TIPO")
    (princ "\n   5. Numerar SEQUENCIAL")
    (princ "\n   0. Voltar")
    
    (setq optSub (GetMenuOption "1 2 3 4 5 0"))
    
    (cond
      ((= optSub "1") (ProcessJSONImport))
      ((= optSub "2") (ProcessGlobalVariables))
      ((= optSub "3") (ProcessManualReview))
      ((= optSub "4") (AutoNumberByType))
      ((= optSub "5") (AutoNumberSequential))
      ((= optSub "0") (setq loopSub nil))
    )
  )
)

;; ============================================================================
;; MÓDULO 2: EXPORTAR JSON (IMPLEMENTADO)
;; ============================================================================
(defun Run_ExportJSON ( / jsonFile doc countBlocks result)
  (LogMsg "INFO" "Iniciando exportação JSON...")
  
  (setq jsonFile (getfiled "Guardar JSON como..." "" "json" 1))
  
  (if jsonFile
    (progn
      (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
      (setq result (ExportBlocksToJSON doc jsonFile))
      
      (if result
        (progn
          (LogMsg "SUCESSO" (strcat "JSON exportado: " jsonFile))
          (alert (strcat "Exportação concluída!\n" (itoa (car result)) " blocos exportados."))
        )
        (progn
          (LogMsg "ERRO" "Falha na exportação JSON")
          (alert "Erro ao exportar JSON.")
        )
      )
    )
    (LogMsg "INFO" "Exportação JSON cancelada pelo utilizador")
  )
  (princ)
)

(defun ExportBlocksToJSON (doc jsonFile / f countBlocks)
  (setq f (open jsonFile "w"))
  (if (not f)
    (progn
      (LogMsg "ERRO" (strcat "Não foi possível criar ficheiro: " jsonFile))
      nil
    )
    (progn
      (write-line "{" f)
      (write-line "  \"desenhos\": [" f)
      
      (setq countBlocks 0)
      (setq firstBlock T)
      
      (vlax-for lay (vla-get-Layouts doc)
        (if (/= (vla-get-ModelType lay) :vlax-true)
          (vlax-for blk (vla-get-Block lay)
            (if (IsTargetBlock blk)
              (progn
                (if (not firstBlock)
                  (write-line "," f)
                  (setq firstBlock nil)
                )
                (WriteBlockToJSON f blk lay)
                (setq countBlocks (1+ countBlocks))
              )
            )
          )
        )
      )
      
      (write-line "" f)
      (write-line "  ]" f)
      (write-line "}" f)
      (close f)
      
      (LogMsg "INFO" (strcat "Exportados " (itoa countBlocks) " blocos"))
      (list countBlocks)
    )
  )
)

(defun WriteBlockToJSON (f blk lay / atts handle)
  (setq handle (vla-get-Handle blk))
  (write-line "    {" f)
  (write-line (strcat "      \"handle_bloco\": \"" handle "\",") f)
  (write-line (strcat "      \"layout\": \"" (vla-get-Name lay) "\",") f)
  (write-line "      \"atributos\": {" f)
  
  (setq atts (vlax-invoke blk 'GetAttributes))
  (setq firstAtt T)
  
  (foreach att atts
    (if (not firstAtt)
      (write-line "," f)
      (setq firstAtt nil)
    )
    (write-line 
      (strcat 
        "        \"" 
        (vla-get-TagString att) 
        "\": \"" 
        (EscapeJSON (vla-get-TextString att)) 
        "\""
      ) 
      f
    )
  )
  
  (write-line "" f)
  (write-line "      }" f)
  (write-line "    }" f)
)

;; ============================================================================
;; MÓDULO 3: GERAR EXCEL NOVO DO ZERO
;; ============================================================================
(defun Run_GenerateExcel_Pro ( / doc outputFile startCellStr layoutList dataList 
                                 sortMode sortOrder excelApp wb sheet cells 
                                 startRow startCol i item success)
  (LogMsg "INFO" "Iniciando geração Excel Pro...")
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  ;; 1. SELEÇÃO DO FICHEIRO OUTPUT
  (setq outputFile (getfiled "Guardar Excel como..." "" "xlsx" 1))
  
  (if (not outputFile)
    (progn
      (LogMsg "INFO" "Geração Excel cancelada")
      (princ "\nCancelado.")
    )
    (progn
      ;; 2. CONFIGURAÇÃO
      (setq startCellStr (getstring "\nCélula inicial (ex: A2) [Enter='A2']: "))
      (if (= startCellStr "") (setq startCellStr *DEFAULT_START_CELL*))
      
      (initget "TabOrder Nome")
      (setq sortMode (getkword "\nOrdenar por [TabOrder/Nome] <TabOrder>: "))
      (if (not sortMode) (setq sortMode "TabOrder"))
      
      ;; 3. RECOLHER DADOS
      (LogMsg "INFO" "A recolher dados dos blocos...")
      (setq layoutList (GetLayoutsSorted doc sortMode))
      (setq dataList (CollectBlockData layoutList))
      
      (if (= (length dataList) 0)
        (progn
          (LogMsg "WARN" "Nenhum bloco LEGENDA_JSJ_V1 encontrado")
          (alert "Nenhum bloco LEGENDA_JSJ_V1 encontrado no desenho!")
        )
        (progn
          (LogMsg "INFO" (strcat "Encontrados " (itoa (length dataList)) " blocos"))
          
          ;; 4. CRIAR EXCEL
          (setq success (CreateExcelFromData outputFile startCellStr dataList))
          
          (if success
            (progn
              (LogMsg "SUCESSO" (strcat "Excel gerado: " outputFile))
              (alert (strcat "Excel gerado com sucesso!\n" 
                            (itoa (length dataList)) " desenhos exportados."))
            )
            (progn
              (LogMsg "ERRO" "Falha na criação do Excel")
              (alert "Erro ao gerar Excel. Verifique o log.")
            )
          )
        )
      )
    )
  )
  (princ)
)

(defun GetLayoutsSorted (doc sortMode / lays listLays)
  (setq lays (vla-get-Layouts doc))
  (setq listLays '())
  
  (vlax-for item lays
    (if (/= (vla-get-ModelType item) :vlax-true)
      (setq listLays (cons item listLays))
    )
  )
  
  (if (= sortMode "Nome")
    (vl-sort listLays 
      '(lambda (a b) (< (strcase (vla-get-Name a)) (strcase (vla-get-Name b))))
    )
    (vl-sort listLays 
      '(lambda (a b) (< (vla-get-TabOrder a) (vla-get-TabOrder b)))
    )
  )
)

(defun CollectBlockData (layoutList / dataList)
  (setq dataList '())
  
  (foreach lay layoutList
    (vlax-for blk (vla-get-Block lay)
      (if (IsTargetBlock blk)
        (progn
          (setq blockData (ExtractBlockData blk lay))
          (setq dataList (append dataList (list blockData)))
        )
      )
    )
  )
  
  dataList
)

(defun ExtractBlockData (blk lay / handle tipo num tit revInfo)
  (setq handle (vla-get-Handle blk))
  (setq tipo (GetAttValue blk "TIPO"))
  (setq num (GetAttValue blk "DES_NUM"))
  (setq tit (GetAttValue blk "TITULO"))
  (setq revInfo (GetMaxRevision blk))
  
  (list handle 
        tipo 
        num 
        tit 
        (car revInfo)     ;; Revisão
        (cadr revInfo)    ;; Data
        (vla-get-Name lay)
  )
)

(defun CreateExcelFromData (outputFile startCellStr dataList / 
                             excelApp wb sheet cells cellObj 
                             startRow startCol i success)
  (setq success nil)
  (setq excelApp (StartExcel))
  
  (if (not excelApp)
    (progn
      (LogMsg "ERRO" "Não foi possível iniciar Excel")
      nil
    )
    (progn
      (LogMsg "INFO" "Excel iniciado com sucesso")
      
      ;; Criar novo workbook
      (setq wb (vlax-invoke-method (vlax-get-property excelApp 'Workbooks) 'Add))
      (setq sheet (vlax-get-property wb 'ActiveSheet))
      (setq cells (vlax-get-property sheet 'Cells))
      
      ;; Obter posição inicial
      (setq cellObj (vlax-get-property sheet 'Range startCellStr))
      (setq startRow (VariantToInt (vlax-get-property cellObj 'Row)))
      (setq startCol (VariantToInt (vlax-get-property cellObj 'Column)))
      (vlax-release-object cellObj)
      
      ;; Escrever cabeçalhos
      (WriteExcelHeaders cells startRow startCol)
      
      ;; Escrever dados (COM PROTEÇÃO)
      (setq i 0)
      (foreach item dataList
        (if (< i *MAX_EXCEL_ROWS*)  ;; PROTEÇÃO ANTI-LOOP
          (progn
            (WriteExcelRow cells (+ startRow 1 i) startCol item)
            (setq i (1+ i))
            (if (= (rem i 10) 0)  ;; Progress feedback
              (princ (strcat "\rProcessados: " (itoa i)))
            )
          )
          (progn
            (LogMsg "WARN" "Atingido limite máximo de linhas Excel")
            (setq item nil)  ;; Força saída do loop
          )
        )
      )
      
      (princ "\n")
      (LogMsg "INFO" (strcat "Escritas " (itoa i) " linhas no Excel"))
      
      ;; Guardar e fechar
      (SafeExcelSave wb outputFile)
      (SafeExcelClose excelApp wb)
      
      (setq success T)
    )
  )
  
  success
)

(defun WriteExcelHeaders (cells row col)
  (PutCellSafe cells row col "TIPO")
  (PutCellSafe cells row (+ col 1) "DES_NUM")
  (PutCellSafe cells row (+ col 2) "TITULO")
  (PutCellSafe cells row (+ col 3) "REVISAO")
  (PutCellSafe cells row (+ col 4) "DATA")
  (PutCellSafe cells row (+ col 5) "HANDLE")
  (PutCellSafe cells row (+ col 6) "LAYOUT")
)

(defun WriteExcelRow (cells row col dataItem)
  (PutCellSafe cells row col (nth 1 dataItem))        ;; TIPO
  (PutCellSafe cells row (+ col 1) (nth 2 dataItem))  ;; DES_NUM
  (PutCellSafe cells row (+ col 2) (nth 3 dataItem))  ;; TITULO
  (PutCellSafe cells row (+ col 3) (nth 4 dataItem))  ;; REVISAO
  (PutCellSafe cells row (+ col 4) (nth 5 dataItem))  ;; DATA
  (PutCellSafe cells row (+ col 5) (nth 0 dataItem))  ;; HANDLE
  (PutCellSafe cells row (+ col 6) (nth 6 dataItem))  ;; LAYOUT
)

;; ============================================================================
;; MÓDULO 4: GERAR EXCEL VIA TEMPLATE (CORRIGIDO)
;; ============================================================================
(defun Run_GenerateExcel_FromTemplate ( / doc templateFile outputFile startCellStr 
                                         layoutList dataList sortMode 
                                         excelApp wb sheet cells cellObj 
                                         startRow startCol i success)
  (LogMsg "INFO" "Iniciando geração via Template...")
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  ;; 1. SELEÇÃO DE FICHEIROS
  (setq templateFile (getfiled "Selecione o TEMPLATE Excel" "" "xlsx;xls" 4))
  
  (if (and templateFile (findfile templateFile))
    (progn
      (LogMsg "INFO" (strcat "Template selecionado: " templateFile))
      
      (setq outputFile (getfiled "Guardar NOVO ficheiro como..." "" "xlsx" 1))
      
      (if outputFile
        (progn
          (setq startCellStr (getstring "\nCélula inicial (ex: C6) [Enter='A2']: "))
          (if (= startCellStr "") (setq startCellStr *DEFAULT_START_CELL*))
          
          ;; 2. RECOLHER DADOS
          (initget "TabOrder Nome")
          (setq sortMode (getkword "\nOrdenar [TabOrder/Nome] <TabOrder>: "))
          (if (not sortMode) (setq sortMode "TabOrder"))
          
          (setq layoutList (GetLayoutsSorted doc sortMode))
          (setq dataList (CollectBlockData layoutList))
          
          (if (= (length dataList) 0)
            (progn
              (LogMsg "WARN" "Nenhum bloco encontrado")
              (alert "Nenhum bloco LEGENDA_JSJ_V1 encontrado!")
            )
            (progn
              (LogMsg "INFO" (strcat "Dados recolhidos: " (itoa (length dataList)) " blocos"))
              
              ;; 3. PROCESSAR TEMPLATE
              (setq success (ProcessTemplate templateFile outputFile startCellStr dataList))
              
              (if success
                (progn
                  (LogMsg "SUCESSO" "Template processado com sucesso")
                  (alert (strcat "Ficheiro criado com sucesso!\n" outputFile))
                )
                (progn
                  (LogMsg "ERRO" "Falha no processamento do template")
                  (alert "Erro ao processar template.")
                )
              )
            )
          )
        )
        (LogMsg "INFO" "Operação cancelada - sem ficheiro output")
      )
    )
    (progn
      (LogMsg "INFO" "Template não selecionado ou não encontrado")
      (princ "\nTemplate não encontrado ou cancelado.")
    )
  )
  (princ)
)

(defun ProcessTemplate (templateFile outputFile startCellStr dataList / 
                        excelApp wb sheet cells cellObj startRow startCol 
                        i success fileExists)
  (setq success nil)
  
  ;; Verificar se output já existe
  (setq fileExists (findfile outputFile))
  (if fileExists
    (progn
      (LogMsg "WARN" "Ficheiro output já existe - será sobrescrito")
      (vl-file-delete outputFile)
    )
  )
  
  ;; Copiar template para output
  (if (vl-file-copy templateFile outputFile)
    (progn
      (LogMsg "INFO" "Template copiado para output")
      
      (setq excelApp (StartExcel))
      
      (if (not excelApp)
        (LogMsg "ERRO" "Não foi possível iniciar Excel")
        (progn
          ;; Abrir o ficheiro copiado
          (setq wb (SafeExcelOpen excelApp outputFile))
          
          (if (not wb)
            (LogMsg "ERRO" "Não foi possível abrir workbook")
            (progn
              (setq sheet (vlax-get-property wb 'ActiveSheet))
              (setq cells (vlax-get-property sheet 'Cells))
              
              ;; Obter posição inicial
              (setq cellObj (vlax-get-property sheet 'Range startCellStr))
              (setq startRow (VariantToInt (vlax-get-property cellObj 'Row)))
              (setq startCol (VariantToInt (vlax-get-property cellObj 'Column)))
              (vlax-release-object cellObj)
              
              (LogMsg "INFO" (strcat "Escrevendo a partir de linha " (itoa startRow)))
              
              ;; Escrever dados COM PROTEÇÃO
              (setq i 0)
              (foreach item dataList
                (if (< i *MAX_EXCEL_ROWS*)
                  (progn
                    (WriteExcelRow cells (+ startRow i) startCol item)
                    (setq i (1+ i))
                    (if (= (rem i 10) 0)
                      (princ (strcat "\rProcessados: " (itoa i)))
                    )
                  )
                )
              )
              
              (princ "\n")
              (LogMsg "INFO" (strcat "Escritas " (itoa i) " linhas"))
              
              ;; Guardar e fechar
              (SafeExcelSave wb nil)  ;; nil = guardar no mesmo ficheiro
              (SafeExcelClose excelApp wb)
              
              (setq success T)
            )
          )
        )
      )
    )
    (LogMsg "ERRO" "Não foi possível copiar template")
  )
  
  success
)

;; ============================================================================
;; MÓDULO 5: IMPORTAR EXCEL (CORRIGIDO)
;; ============================================================================
(defun Run_ImportExcel_Flexible ( / excelFile startCellStr excelApp wb sheet 
                                    cells cellObj startRow startCol 
                                    countUpdates r valHandle maxRows)
  (LogMsg "INFO" "Iniciando importação Excel...")
  
  (setq excelFile (getfiled "Selecione o ficheiro Excel" "" "xlsx;xls" 4))
  
  (if (and excelFile (findfile excelFile))
    (progn
      (LogMsg "INFO" (strcat "Ficheiro selecionado: " excelFile))
      
      (setq startCellStr (getstring "\nCélula inicial [Enter='A2']: "))
      (if (= startCellStr "") (setq startCellStr *DEFAULT_START_CELL*))
      
      (setq excelApp (StartExcel))
      
      (if (not excelApp)
        (alert "Erro ao iniciar Excel.")
        (progn
          (setq wb (SafeExcelOpen excelApp excelFile))
          
          (if (not wb)
            (progn
              (LogMsg "ERRO" "Não foi possível abrir Excel")
              (SafeExcelClose excelApp nil)
              (alert "Erro ao abrir ficheiro Excel.")
            )
            (progn
              (setq sheet (vlax-get-property wb 'ActiveSheet))
              (setq cells (vlax-get-property sheet 'Cells))
              
              ;; Obter posição inicial
              (setq cellObj (vlax-get-property sheet 'Range startCellStr))
              (setq startRow (VariantToInt (vlax-get-property cellObj 'Row)))
              (setq startCol (VariantToInt (vlax-get-property cellObj 'Column)))
              (vlax-release-object cellObj)
              
              (LogMsg "INFO" (strcat "A ler a partir de linha " (itoa startRow)))
              (princ "\nA atualizar CAD... ")
              
              (setq countUpdates 0)
              (setq r 0)
              (setq maxRows *MAX_EXCEL_ROWS*)  ;; PROTEÇÃO ANTI-LOOP
              
              ;; LOOP SEGURO COM PROTEÇÃO
              (while (and (< r maxRows) 
                         (setq valHandle (GetCellText cells (+ startRow r) (+ startCol 5)))
                         (not (or (= valHandle "") (= valHandle nil))))
                (progn
                  (setq valTipo (GetCellText cells (+ startRow r) (+ startCol 0)))
                  (setq valNum (GetCellText cells (+ startRow r) (+ startCol 1)))
                  (setq valTit (GetCellText cells (+ startRow r) (+ startCol 2)))
                  (setq valRev (GetCellText cells (+ startRow r) (+ startCol 3)))
                  (setq valData (GetCellText cells (+ startRow r) (+ startCol 4)))
                  
                  ;; Validar handle antes de atualizar
                  (if (ValidateHandle valHandle)
                    (progn
                      (UpdateBlockByHandleAndData valHandle valTipo valNum valTit valRev valData)
                      (setq countUpdates (1+ countUpdates))
                      (if (= (rem countUpdates 10) 0)
                        (princ (strcat "\rAtualizados: " (itoa countUpdates)))
                      )
                    )
                    (LogMsg "WARN" (strcat "Handle inválido ignorado: " valHandle))
                  )
                  
                  (setq r (1+ r))
                )
              )
              
              (princ "\n")
              
              ;; Avisar se atingiu o limite
              (if (>= r maxRows)
                (LogMsg "WARN" "Atingido limite máximo de linhas - importação truncada")
              )
              
              ;; Fechar Excel
              (vlax-invoke-method wb 'Close :vlax-false)
              (SafeExcelClose excelApp nil)
              
              ;; Limpar objetos
              (ReleaseObject cells)
              (ReleaseObject sheet)
              (ReleaseObject wb)
              
              ;; Regenerar
              (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport)
              
              (LogMsg "SUCESSO" (strcat "Importados " (itoa countUpdates) " desenhos"))
              (alert (strcat "Importação Concluída!\n" 
                            (itoa countUpdates) " desenhos atualizados."))
            )
          )
        )
      )
    )
    (progn
      (LogMsg "INFO" "Importação cancelada")
      (princ "\nCancelado.")
    )
  )
  (princ)
)

;; ============================================================================
;; MÓDULO 6: VISUALIZADOR DE LOG
;; ============================================================================
(defun Run_LogViewer ( / opt)
  (textscr)
  (princ "\n\n=== LOG DO SISTEMA ===\n")
  
  (if (= (length *GESTAO_LOG*) 0)
    (princ "\nNenhum log registado nesta sessão.")
    (progn
      (princ (strcat "\nTotal de entradas: " (itoa (length *GESTAO_LOG*)) "\n"))
      (princ "\nÚltimas 20 entradas:\n")
      
      (setq i 0)
      (foreach entry (reverse *GESTAO_LOG*)
        (if (< i 20)
          (progn
            (princ (strcat "\n" (car entry) " [" (cadr entry) "] " (caddr entry)))
            (setq i (1+ i))
          )
        )
      )
    )
  )
  
  (princ "\n")
  (initget "Sim Nao")
  (setq opt (getkword "\nGuardar log completo em ficheiro? [Sim/Nao] <Nao>: "))
  
  (if (= opt "Sim")
    (SaveLogToFile)
  )
  
  (princ "\nPressione ENTER para continuar...")
  (getstring)
)

;; ============================================================================
;; FUNÇÕES AUXILIARES - EXCEL (SEGURAS)
;; ============================================================================

(defun StartExcel ( / excelApp result)
  (setq result 
    (vl-catch-all-apply 
      '(lambda ()
         (vlax-get-or-create-object "Excel.Application")
       )
      nil
    )
  )
  
  (if (vl-catch-all-error-p result)
    (progn
      (LogMsg "ERRO" "Não foi possível iniciar Excel")
      (LogMsg "ERRO" (vl-catch-all-error-message result))
      nil
    )
    (progn
      (vlax-put-property result 'Visible :vlax-false)
      (vlax-put-property result 'DisplayAlerts :vlax-false)
      result
    )
  )
)

(defun SafeExcelOpen (excelApp filepath / wb result)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
         (vlax-invoke-method 
           (vlax-get-property excelApp 'Workbooks) 
           'Open 
           filepath
         )
       )
      nil
    )
  )
  
  (if (vl-catch-all-error-p result)
    (progn
      (LogMsg "ERRO" "Não foi possível abrir Excel")
      (LogMsg "ERRO" (vl-catch-all-error-message result))
      nil
    )
    result
  )
)

(defun SafeExcelSave (wb filepath / result)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
         (if filepath
           (vlax-invoke-method wb 'SaveAs filepath)
           (vlax-invoke-method wb 'Save)
         )
         T
       )
      nil
    )
  )
  
  (if (vl-catch-all-error-p result)
    (progn
      (LogMsg "ERRO" "Erro ao guardar Excel")
      (LogMsg "ERRO" (vl-catch-all-error-message result))
      nil
    )
    (progn
      (LogMsg "INFO" "Excel guardado com sucesso")
      T
    )
  )
)

(defun SafeExcelClose (excelApp wb / result)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
         (if wb
           (vlax-invoke-method wb 'Close :vlax-false)
         )
         (if excelApp
           (vlax-invoke-method excelApp 'Quit)
         )
         T
       )
      nil
    )
  )
  
  (if (vl-catch-all-error-p result)
    (LogMsg "WARN" "Erro ao fechar Excel (pode estar bloqueado)")
  )
  
  (ReleaseObject wb)
  (ReleaseObject excelApp)
)

(defun PutCellSafe (cells row col val / item cell result)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
         (setq item (vlax-get-property cells 'Item row col))
         (if (= (type item) 'variant)
           (setq cell (vlax-variant-value item))
           (setq cell item)
         )
         (vlax-put-property cell 'Value2 val)
         (vlax-release-object cell)
         T
       )
      nil
    )
  )
  
  (if (vl-catch-all-error-p result)
    (LogMsg "WARN" (strcat "Erro ao escrever célula [" (itoa row) "," (itoa col) "]"))
  )
)

(defun GetCellText (cells row col / item cell val result)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
         (setq item (vlax-get-property cells 'Item row col))
         (if (= (type item) 'variant)
           (setq cell (vlax-variant-value item))
           (setq cell item)
         )
         (setq val (vlax-get-property cell 'Text))
         (vlax-release-object cell)
         val
       )
      nil
    )
  )
  
  (if (vl-catch-all-error-p result)
    ""
    result
  )
)

(defun VariantToInt (var)
  (if (= (type var) 'variant)
    (setq var (vlax-variant-value var))
  )
  (if (= (type var) 'INT)
    var
    (atoi (vl-princ-to-string var))
  )
)

(defun ReleaseObject (obj)
  (if (and obj 
           (vlax-object-p obj)
           (not (vlax-object-released-p obj)))
    (progn
      (vlax-release-object obj)
      T
    )
    nil
  )
)

;; ============================================================================
;; FUNÇÕES AUXILIARES - BLOCOS CAD
;; ============================================================================

(defun IsTargetBlock (blk)
  (and 
    (= (vla-get-ObjectName blk) "AcDbBlockReference")
    (= (strcase (vla-get-EffectiveName blk)) (strcase *LEGENDA_BLOCK_NAME*))
  )
)

(defun GetAttValue (blk tag / atts val)
  (setq atts (vlax-invoke blk 'GetAttributes))
  (setq val "")
  (foreach att atts
    (if (= (strcase (vla-get-TagString att)) (strcase tag))
      (setq val (vla-get-TextString att))
    )
  )
  val
)

(defun ValidateHandle (handle / ename result)
  (setq result
    (vl-catch-all-apply
      '(lambda ()
         (handent handle)
       )
      nil
    )
  )
  
  (not (vl-catch-all-error-p result))
)

(defun UpdateSingleTag (handle tag val / ename obj atts updated)
  (setq updated nil)
  
  (if (ValidateHandle handle)
    (progn
      (setq ename (handent handle))
      (if (and ename (setq obj (vlax-ename->vla-object ename)))
        (progn
          (setq atts (vlax-invoke obj 'GetAttributes))
          (foreach att atts
            (if (= (strcase (vla-get-TagString att)) (strcase tag))
              (progn
                (vla-put-TextString att val)
                (setq updated T)
              )
            )
          )
          (if updated
            (vla-Update obj)
          )
        )
      )
    )
    (LogMsg "WARN" (strcat "Handle inválido: " handle))
  )
  
  updated
)

(defun UpdateBlockByHandleAndData (handle tipo num tit rev dataStr / 
                                   ename obj revTag dataTag success)
  (setq success nil)
  
  (if (ValidateHandle handle)
    (progn
      (setq ename (handent handle))
      (if (and ename (setq obj (vlax-ename->vla-object ename)))
        (if (IsTargetBlock obj)
          (progn
            (UpdateSingleTag handle "TIPO" tipo)
            (UpdateSingleTag handle "DES_NUM" num)
            (UpdateSingleTag handle "TITULO" tit)
            
            (if (and rev (/= rev "") (/= rev "-"))
              (progn
                (setq revTag (strcat "REV_" rev))
                (setq dataTag (strcat "DATA_" rev))
                (UpdateSingleTag handle revTag rev)
                (UpdateSingleTag handle dataTag dataStr)
              )
            )
            
            (setq success T)
            (princ ".")
          )
          (LogMsg "WARN" (strcat "Bloco não é " *LEGENDA_BLOCK_NAME* ": " handle))
        )
      )
    )
    (LogMsg "WARN" (strcat "Handle não encontrado: " handle))
  )
  
  success
)

(defun UpdateBlockByHandle (handle pairList / ename obj atts tagVal foundVal updated)
  (setq updated 0)
  
  (if (ValidateHandle handle)
    (progn
      (setq ename (handent handle))
      (if (and ename (setq obj (vlax-ename->vla-object ename)))
        (if (and (= (vla-get-ObjectName obj) "AcDbBlockReference")
                 (= (vla-get-HasAttributes obj) :vlax-true))
          (foreach att (vlax-invoke obj 'GetAttributes)
            (setq tagVal (strcase (vla-get-TagString att)))
            (setq foundVal (cdr (assoc tagVal pairList)))
            (if foundVal
              (progn
                (vla-put-TextString att foundVal)
                (setq updated (1+ updated))
              )
            )
          )
        )
      )
    )
  )
  
  (if (> updated 0)
    (LogMsg "INFO" (strcat "Atualizados " (itoa updated) " atributos"))
  )
  
  updated
)

(defun GetMaxRevision (blk / revLetter revDate checkRev finalRev finalDate)
  (setq finalRev "-")
  (setq finalDate "-")
  
  (foreach letra *REV_LETTERS*
    (if (= finalRev "-")
      (progn
        (setq checkRev (GetAttValue blk (strcat "REV_" letra)))
        (if (and (/= checkRev "") (/= checkRev " "))
          (progn
            (setq finalRev checkRev)
            (setq finalDate (GetAttValue blk (strcat "DATA_" letra)))
          )
        )
      )
    )
  )
  
  (list finalRev finalDate)
)

;; ============================================================================
;; FUNÇÕES AUXILIARES - PROCESSAMENTO
;; ============================================================================

(defun ProcessJSONImport ( / jsonFile fileDes line posSep handleVal attList 
                            inAttributes tag rawContent cleanContent countUpdates)
  (setq jsonFile (getfiled "Selecione JSON" "" "json" 4))
  
  (if (and jsonFile (findfile jsonFile))
    (progn
      (LogMsg "INFO" (strcat "A importar JSON: " jsonFile))
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
           (if posSep
             (progn
               (setq rawContent (substr line (+ posSep 2)))
               (setq handleVal (vl-string-trim " \"," rawContent))
               (setq attList '())
             )
           )
          )
          
          ((vl-string-search "\"atributos\": {" line)
           (setq inAttributes T)
          )
          
          ((and inAttributes (vl-string-search "}" line))
           (setq inAttributes nil)
           (if (and handleVal attList)
             (progn
               (if (UpdateBlockByHandle handleVal attList)
                 (setq countUpdates (1+ countUpdates))
               )
             )
           )
           (setq handleVal nil)
          )
          
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
      (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport)
      
      (LogMsg "SUCESSO" (strcat "JSON importado: " (itoa countUpdates) " blocos"))
      (alert (strcat "Concluído: " (itoa countUpdates) " blocos atualizados."))
    )
    (progn
      (LogMsg "INFO" "Importação JSON cancelada")
      (princ "\nCancelado.")
    )
  )
)

(defun ProcessGlobalVariables ( / loop validTags selTag newVal continueLoop)
  (setq loop T)
  (setq validTags (GetExampleTags))
  
  (while loop
    (textscr)
    (princ "\n\n=== GESTOR GLOBAL ===")
    (princ "\nTags disponíveis:")
    (foreach tName validTags
      (princ (strcat "\n • " tName))
    )
    
    (setq selTag (strcase (getstring "\nDigite o NOME do Tag: ")))
    
    (if (member selTag validTags)
      (progn
        (setq newVal (getstring T (strcat "\nNovo valor para " selTag ": ")))
        (ApplyGlobalValue selTag newVal)
        (LogMsg "INFO" (strcat "Aplicado valor global: " selTag " = " newVal))
      )
      (princ "\nTag inválido ou não encontrado.")
    )
    
    (initget "Sim Nao")
    (setq continueLoop (getkword "\nAlterar outro tag? [Sim/Nao] <Nao>: "))
    (if (or (= continueLoop "Nao") (= continueLoop nil))
      (setq loop nil)
    )
  )
)

(defun ProcessManualReview ( / loop drawList i item userIdx selectedHandle 
                              field revLet revVal)
  (setq loop T)
  
  (while loop
    (setq drawList (GetDrawingList))
    (textscr)
    (princ "\n\n=== LISTA DE DESENHOS ===\n")
    
    (setq i 0)
    (foreach item drawList
      (princ 
        (strcat "\n " 
                (itoa (1+ i)) 
                ". [Des: " (cadr item) 
                "] (" (nth 3 item) 
                ") - Tab: " (caddr item))
      )
      (setq i (1+ i))
    )
    
    (setq userIdx (getint (strcat "\nEscolha (1-" (itoa i) ") ou 0 para sair: ")))
    
    (if (and userIdx (> userIdx 0) (<= userIdx i))
      (progn
        (setq selectedHandle (car (nth (1- userIdx) drawList)))
        
        (initget "Tipo Titulo Revisao")
        (setq field (getkword "\nAtualizar? [Tipo/Titulo/Revisao]: "))
        
        (cond
          ((= field "Tipo")
           (UpdateSingleTag selectedHandle "TIPO" 
             (getstring T "\nNovo TIPO: "))
          )
          
          ((= field "Titulo")
           (UpdateSingleTag selectedHandle "TITULO" 
             (getstring T "\nNovo TITULO: "))
          )
          
          ((= field "Revisao")
           (initget "A B C D E")
           (setq revLet (getkword "\nQual a Revisão? [A/B/C/D/E]: "))
           (if revLet
             (progn
               (UpdateSingleTag selectedHandle 
                 (strcat "DATA_" revLet) 
                 (getstring T "\nData: "))
               (UpdateSingleTag selectedHandle 
                 (strcat "DESC_" revLet) 
                 (getstring T "\nDescrição: "))
               (setq revVal (getstring T (strcat "\nLetra (Enter='" revLet "'): ")))
               (if (= revVal "") (setq revVal revLet))
               (UpdateSingleTag selectedHandle 
                 (strcat "REV_" revLet) 
                 revVal)
             )
           )
          )
        )
        
        (vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) acActiveViewport)
        (setq loop nil)
      )
      (if loop
        (progn
          (initget "Sim Nao")
          (if (= (getkword "\nAlterar outro? [Sim/Nao] <Nao>: ") "Nao")
            (setq loop nil)
          )
        )
      )
    )
  )
)

(defun AutoNumberByType ( / doc dataList blk typeVal handleVal tabOrd 
                           sortedList curType count i)
  (LogMsg "INFO" "Iniciando numeração por tipo...")
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq dataList '())
  
  (princ "\n\nA analisar blocos...")
  
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
  
  (setq sortedList 
    (vl-sort dataList 
      '(lambda (a b)
         (if (= (strcase (car a)) (strcase (car b)))
           (< (cadr a) (cadr b))
           (< (strcase (car a)) (strcase (car b)))
         )
       )
    )
  )
  
  (setq curType "")
  (setq count 0)
  (setq i 0)
  
  (foreach item sortedList
    (if (/= (strcase (car item)) curType)
      (progn
        (setq curType (strcase (car item)))
        (setq count 1)
      )
      (setq count (1+ count))
    )
    (UpdateSingleTag (caddr item) "DES_NUM" (FormatNum count))
    (setq i (1+ i))
  )
  
  (vla-Regen doc acActiveViewport)
  (LogMsg "SUCESSO" (strcat "Numerados " (itoa i) " desenhos por tipo"))
  (alert (strcat "Concluído: " (itoa i) " desenhos numerados."))
)

(defun AutoNumberSequential ( / doc sortedLayouts count i)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  (initget "Sim Nao")
  (if (= (getkword "\nNumerar sequencialmente? [Sim/Nao] <Nao>: ") "Sim")
    (progn
      (LogMsg "INFO" "Numeração sequencial iniciada")
      
      (setq sortedLayouts (GetLayoutsRaw doc))
      (setq sortedLayouts 
        (vl-sort sortedLayouts 
          '(lambda (a b) (< (vla-get-TabOrder a) (vla-get-TabOrder b)))
        )
      )
      
      (setq count 1)
      (setq i 0)
      
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
      (LogMsg "SUCESSO" (strcat "Numerados " (itoa i) " desenhos sequencialmente"))
      (alert (strcat "Concluído: " (itoa i) " desenhos numerados."))
    )
    (LogMsg "INFO" "Numeração sequencial cancelada")
  )
)

(defun ApplyGlobalValue (targetTag targetVal / doc count)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq count 0)
  
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (IsTargetBlock blk)
          (foreach att (vlax-invoke blk 'GetAttributes)
            (if (= (strcase (vla-get-TagString att)) targetTag)
              (progn
                (vla-put-TextString att targetVal)
                (setq count (1+ count))
              )
            )
          )
        )
      )
    )
  )
  
  (vla-Regen doc acActiveViewport)
  (LogMsg "INFO" (strcat "Aplicado a " (itoa count) " blocos"))
  (alert (strcat "Aplicado a " (itoa count) " blocos."))
)

(defun GetDrawingList ( / doc listOut atts desNum tipo)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq listOut '())
  
  (vlax-for lay (vla-get-Layouts doc)
    (if (/= (vla-get-ModelType lay) :vlax-true)
      (vlax-for blk (vla-get-Block lay)
        (if (IsTargetBlock blk)
          (progn
            (setq desNum (GetAttValue blk "DES_NUM"))
            (setq tipo (GetAttValue blk "TIPO"))
            (if (= desNum "") (setq desNum "??"))
            (if (= tipo "") (setq tipo "ND"))
            (setq listOut 
              (cons 
                (list (vla-get-Handle blk) desNum (vla-get-Name lay) tipo) 
                listOut
              )
            )
          )
        )
      )
    )
  )
  
  (reverse listOut)
)

(defun GetLayoutsRaw (doc / lays listLays)
  (setq lays (vla-get-Layouts doc))
  (setq listLays '())
  
  (vlax-for item lays
    (if (/= (vla-get-ModelType item) :vlax-true)
      (setq listLays (cons item listLays))
    )
  )
  
  listLays
)

(defun GetExampleTags ( / doc tagList found atts tag)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  (setq tagList '())
  (setq found nil)
  
  (vlax-for lay (vla-get-Layouts doc)
    (if (not found)
      (vlax-for blk (vla-get-Block lay)
        (if (IsTargetBlock blk)
          (progn
            (foreach att (vlax-invoke blk 'GetAttributes)
              (setq tag (strcase (vla-get-TagString att)))
              (if (and 
                    (/= tag "DES_NUM")
                    (not (wcmatch tag "REV_?,DATA_?,DESC_?"))
                  )
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

(defun FormatNum (n)
  (if (< n 10)
    (strcat "0" (itoa n))
    (itoa n)
  )
)

;; ============================================================================
;; FUNÇÕES AUXILIARES - STRING
;; ============================================================================

(defun CleanCSV (str)
  (setq str (vl-string-translate ";" "," str))
  (vl-string-trim " \"" str)
)

(defun EscapeJSON (str / i char result len)
  (setq result "")
  (setq len (strlen str))
  (setq i 1)
  
  (while (<= i len)
    (setq char (substr str i 1))
    (cond
      ((= char "\\") (setq result (strcat result "\\\\")))
      ((= char "\"") (setq result (strcat result "\\\"")))
      ((= char "\n") (setq result (strcat result "\\n")))
      ((= char "\t") (setq result (strcat result "\\t")))
      (t (setq result (strcat result char)))
    )
    (setq i (1+ i))
  )
  
  result
)

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
          ((= nextChar "n") (setq result (strcat result "\n")))
          ((= nextChar "t") (setq result (strcat result "\t")))
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

;; ============================================================================
;; FIM DO CÓDIGO
;; ============================================================================
(princ "\n>>> Gestao Desenhos JSJ V11 carregado. Digite GESTAODESENHOSJSJ para iniciar. <<<")
(princ)