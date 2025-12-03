(defun c:GERAR_LISTA ( / doc path name csvFile fileDes layouts blkName targetBlockName 
                         atts valRev valData valTipo valNum valTit maxRev 
                         revLetra revData layoutList item dataList sortMode sortOrder)
  (vl-load-com)
  (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
  
  ;; --- CONFIGURAÇÃO ---
  (setq targetBlockName "LEGENDA_JSJ_V1")

  ;; 1. RECOLHER DADOS PARA MEMÓRIA
  (princ "\nA ler dados de todos os layouts... Aguarde.")
  (setq layoutList (GetLayoutsRaw doc))
  (setq dataList '()) ;; Lista que vai guardar ((Tipo Num Tit Rev Data) ...)

  (foreach lay layoutList
    (vlax-for blk (vla-get-Block lay)
      (if (and (= (vla-get-ObjectName blk) "AcDbBlockReference")
               (= (strcase (vla-get-EffectiveName blk)) (strcase targetBlockName)))
        (progn
          ;; Extração
          (setq valTipo (GetAttValue blk "TIPO"))
          (setq valNum  (GetAttValue blk "DES_NUM"))
          (setq valTit  (GetAttValue blk "TITULO"))
          
          ;; Revisão Máxima
          (setq maxRev (GetMaxRevision blk)) 
          (setq revLetra (car maxRev))
          (setq revData (cadr maxRev))

          ;; Limpeza (Remove ; e aspas para não partir CSV)
          (setq valTipo (CleanCSV valTipo))
          (setq valNum  (CleanCSV valNum))
          (setq valTit  (CleanCSV valTit))
          (setq revLetra (CleanCSV revLetra))
          (setq revData (CleanCSV revData))

          ;; Adiciona à lista de dados: (TIPO NUM TIT REV DATA)
          (setq dataList (cons (list valTipo valNum valTit revLetra revData) dataList))
        )
      )
    )
  )

  ;; 2. PERGUNTAS DE ORDENAÇÃO
  (initget "Tipo Numero")
  (setq sortMode (getkword "\nComo deseja ordenar a lista? [Tipo/Numero] <Numero>: "))
  (if (not sortMode) (setq sortMode "Numero"))

  (if (= sortMode "Tipo")
    (progn
      (initget "Ascendente Descendente")
      (setq sortOrder (getkword "\nQual a ordem do TIPO? [Ascendente/Descendente] <Ascendente>: "))
      (if (not sortOrder) (setq sortOrder "Ascendente"))
    )
  )

  ;; 3. APLICAR LÓGICA DE ORDENAÇÃO
  (princ "\nA ordenar...")
  
  (cond
    ;; CASO A: ORDENAR POR TIPO (Com sub-ordenação por número)
    ((= sortMode "Tipo")
     (setq dataList 
       (vl-sort dataList 
         '(lambda (a b)
            (if (= (strcase (nth 0 a)) (strcase (nth 0 b)))
              ;; Se Tipos forem iguais, ordena pelo Número (item 1)
              (< (strcase (nth 1 a)) (strcase (nth 1 b)))
              ;; Se Tipos forem diferentes, ordena pelo Tipo (item 0)
              (if (= sortOrder "Descendente")
                  (> (strcase (nth 0 a)) (strcase (nth 0 b))) ;; Z-A
                  (< (strcase (nth 0 a)) (strcase (nth 0 b))) ;; A-Z
              )
            )
          )
       )
     )
    )
    ;; CASO B: ORDENAR POR NÚMERO
    ((= sortMode "Numero")
     (setq dataList 
       (vl-sort dataList 
         '(lambda (a b) (< (strcase (nth 1 a)) (strcase (nth 1 b))))
       )
     )
    )
  )

  ;; 4. ESCREVER CSV
  (setq path (vla-get-Path doc))
  (if (= path "") (progn (alert "Grave o desenho primeiro!") (exit)))
  (setq name (vl-filename-base (vla-get-Name doc)))
  (setq csvFile (strcat path "\\" name "_ListaDesenhos.csv"))
  
  (setq fileDes (open csvFile "w"))
  
  ;; Cabeçalho Novo
  (write-line "Tipo;Número de Desenho;Título;Revisão;Data" fileDes)

  ;; Loop de escrita
  (foreach row dataList
    (write-line (strcat (nth 0 row) ";" (nth 1 row) ";" (nth 2 row) ";" (nth 3 row) ";" (nth 4 row)) fileDes)
  )

  (close fileDes)
  (alert (strcat "Lista gerada e ordenada por " (strcase sortMode) "!\n\nFicheiro:\n" csvFile))
  (princ)
)

;; --- FUNÇÕES AUXILIARES ---

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

(defun GetMaxRevision (blk / atts revLetter revDate checkRev finalRev finalDate)
  (setq atts (vlax-invoke blk 'GetAttributes))
  (setq finalRev "-")
  (setq finalDate "-")
  
  (foreach letra '("E" "D" "C" "B" "A")
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

(defun CleanCSV (str)
  (setq str (vl-string-translate ";" "," str)) ;; Troca ; por ,
  (vl-string-trim " \"" str) ;; Remove aspas e espaços das pontas
)