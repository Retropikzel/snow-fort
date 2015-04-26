
(import (scheme base) (scheme write) (scheme file) (srfi 1)
        (chibi config) (chibi pathname) (chibi regexp) (chibi zlib)
        (chibi string) (chibi log) (chibi net servlet) (chibi io)
        (chibi filesystem) (chibi tar) (chibi crypto rsa)
        (chibi snow fort) (chibi snow package) (chibi snow utils))

(define (path-top path)
  (substring path 0 (string-find path #\/)))

(define (tar-top tar)
  (path-top (car (tar-files tar))))

(define (handle-upload cfg request up)
  (guard (exn
          (else
           (log-error "upload error: " exn)
           (fail "unknown error processing snowball: "
                 "the file should be a gzipped tar file "
                 "containing a single directory with a "
                 "packages.scm file, plus a valid signature file")))
    (let* ((raw-data (upload->bytevector up))
           (snowball (maybe-gunzip raw-data))
           (pkg (extract-snowball-package snowball))
           (sig-spec (guard (exn (else #f))
                       (upload->sexp (request-upload request "sig"))))
           (email (and (pair? sig-spec) (assoc-get (cdr sig-spec) 'email)))
           (password (request-param request "pw"))
           (password-given? (and password (not (equal? password ""))))
           (signed? (and (pair? sig-spec) (assoc-get (cdr sig-spec) 'rsa))))
      (cond
       ((invalid-package-reason pkg)
        => fail)
       ((not sig-spec)
        (fail "a sig with at least email is required"))
       ((and (not password-given?) (not signed?))
        (fail "neither password nor signature given for upload"))
       ((and password-given?
             (not (equal? password (get-user-password cfg email))))
        (fail "invalid password"))
       ((and signed?
             (invalid-signature-reason cfg sig-spec snowball))
        => fail)
       (else
        (let* ((dir (package-dir email pkg))
               (base (or (upload-filename up) "package.tgz"))
               (path (make-path dir base))
               (local-path (static-local-path cfg path))
               (local-dir (path-directory local-path))
               (url (static-url cfg path))
               (pkg2
                `(,(car pkg)
                  (url ,url)
                  (size ,(bytevector-length snowball))
                  ,sig-spec
                  ,@(remove
                     (lambda (x)
                       (and (pair? x) (memq (car x) '(url size))))
                     (cdr pkg)))))
          (cond
           ((file-exists? local-dir)
            (fail "the same version of this package already exists: "
                  (package-name pkg) ": " (package-version pkg)))
           (else
            (create-directory* (path-directory local-path))
            (upload-save up local-path)
            (update-repo-package cfg pkg2)
            (guard (exn (else (log-error "failed to save docs: " exn)))
              (cond
               ((cond ((assoc-get pkg 'manual)
                       => (lambda (doc-file)
                            (let ((file (make-path (tar-top snowball)
                                                   doc-file)))
                              (tar-extract-file snowball file))))
                      (else #f))
                => (lambda (bv)
                     (let ((out (open-binary-output-file
                                 (static-local-path
                                  cfg
                                  (make-path dir "index.html")))))
                       (write-bytevector bv out)
                       (close-output-port out))))))
            `(span "Thanks for uploading! "
                   "Users can now install your package.")))))))))

(servlet-run
 (lambda (cfg request next restart)
   (servlet-parse-body! request)
   (respond
    cfg
    request
    (lambda (content)
      (page
       `(div
         (form (@ (enctype . "multipart/form-data")
                  (method . "POST"))
           "Upload package: "
           (input (@ (type . "file") (name . "u")))
           "Signature: "
           (input (@ (type . "file") (name . "sig")))
           (input (@ (type . "submit") (value . "send"))))
         ,@(content
            (cond
             ((request-upload request "u")
              => (lambda (up) (handle-upload cfg request up)))
             (else
              '())))))))))
