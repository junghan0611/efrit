;;; efrit-openrouter.el --- OpenRouter API support for Efrit -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Junghan Kim

;; Author: Junghan Kim <junghanacs@gmail.com>
;; Keywords: ai, tools, openrouter
;; Version: 0.1.0

;;; Commentary:

;; OpenRouter API support for Efrit using advice pattern.
;; This file adds OpenRouter compatibility without modifying upstream code.
;;
;; Usage:
;;   (require 'efrit-openrouter)
;;   (setq efrit-api-backend 'openrouter)
;;   (setq efrit-openrouter-model "anthropic/claude-sonnet-4")
;;
;; The advice functions automatically convert:
;;   - Request format: Anthropic -> OpenRouter (OpenAI-compatible)
;;   - Response format: OpenRouter -> Anthropic (for efrit-executor parsing)
;;   - Tool schema: Anthropic -> OpenAI function calling format

;;; Code:

(require 'efrit-common)
(require 'json)

;; Declare url.el dynamic variables
(defvar url-request-method)
(defvar url-request-extra-headers)
(defvar url-request-data)

;; Declare efrit-chat variables and functions
(defvar efrit-enable-tools)
(defvar efrit-max-tokens)
(defvar efrit-temperature)
(declare-function efrit-tools-system-prompt "efrit-tools")

;;; Customization

(defcustom efrit-openrouter-model "anthropic/claude-sonnet-4"
  "Model to use with OpenRouter backend.
Format: provider/model-name (e.g., 'anthropic/claude-sonnet-4')."
  :type 'string
  :group 'efrit)

;;; Tool Schema Conversion

(defun efrit-openrouter--convert-tool (tool)
  "Convert single Anthropic-style TOOL to OpenAI function format."
  (let ((name (cdr (assoc "name" tool)))
        (description (cdr (assoc "description" tool)))
        (input-schema (cdr (assoc "input_schema" tool))))
    `(("type" . "function")
      ("function" . (("name" . ,name)
                     ("description" . ,description)
                     ("parameters" . ,input-schema))))))

(defun efrit-openrouter--convert-tools (tools)
  "Convert Anthropic-style TOOLS array to OpenRouter/OpenAI format."
  (if (vectorp tools)
      (vconcat (mapcar #'efrit-openrouter--convert-tool (append tools nil)))
    (vconcat (mapcar #'efrit-openrouter--convert-tool tools))))

;;; Request Format Conversion

(defun efrit-openrouter--convert-request (request-data)
  "Convert Anthropic REQUEST-DATA to OpenRouter format.
- Move 'system' into 'messages' array as first message
- Convert 'tools' to OpenAI function calling format
- Replace model with OpenRouter model name"
  (let* ((model efrit-openrouter-model)
         (max-tokens (cdr (assoc "max_tokens" request-data)))
         (temperature (cdr (assoc "temperature" request-data)))
         (system-prompt (cdr (assoc "system" request-data)))
         (messages (cdr (assoc "messages" request-data)))
         (tools (cdr (assoc "tools" request-data)))
         ;; Build messages with system prompt at the beginning
         (openrouter-messages
          (vconcat
           (when system-prompt
             `[(("role" . "system")
                ("content" . ,system-prompt))])
           messages)))
    ;; Build OpenRouter request
    `(("model" . ,model)
      ("max_tokens" . ,max-tokens)
      ("temperature" . ,(or temperature 0.0))
      ("messages" . ,openrouter-messages)
      ,@(when tools
          `(("tools" . ,(efrit-openrouter--convert-tools tools)))))))

;;; Response Format Conversion

(defun efrit-openrouter--convert-tool-call (tool-call)
  "Convert OpenAI TOOL-CALL to Anthropic tool_use format."
  (let* ((id (cdr (assoc "id" tool-call)))
         (function (cdr (assoc "function" tool-call)))
         (name (cdr (assoc "name" function)))
         (arguments-str (cdr (assoc "arguments" function)))
         (arguments (if (stringp arguments-str)
                        (condition-case nil
                            (json-read-from-string arguments-str)
                          (error arguments-str))
                      arguments-str)))
    `(("type" . "tool_use")
      ("id" . ,id)
      ("name" . ,name)
      ("input" . ,arguments))))

(defun efrit-openrouter--convert-response (response)
  "Convert OpenRouter RESPONSE to Anthropic format for efrit-executor parsing."
  (when response
    (let* ((choices (gethash "choices" response))
           (first-choice (and choices (> (length choices) 0) (aref choices 0)))
           (message (and first-choice (gethash "message" first-choice)))
           (finish-reason (and first-choice (gethash "finish_reason" first-choice)))
           (content-text (and message (gethash "content" message)))
           (tool-calls (and message (gethash "tool_calls" message)))
           ;; Build Anthropic-style content array
           (content-items '()))

      ;; Add text content if present
      (when (and content-text (not (string-empty-p content-text)))
        (push `(("type" . "text") ("text" . ,content-text)) content-items))

      ;; Convert tool calls to Anthropic format
      (when tool-calls
        (dotimes (i (length tool-calls))
          (let ((tool-call (aref tool-calls i)))
            (push (efrit-openrouter--convert-tool-call
                   (if (hash-table-p tool-call)
                       ;; Convert hash-table to alist for processing
                       `(("id" . ,(gethash "id" tool-call))
                         ("function" . (("name" . ,(gethash "name" (gethash "function" tool-call)))
                                       ("arguments" . ,(gethash "arguments" (gethash "function" tool-call))))))
                     tool-call))
                  content-items))))

      ;; Build Anthropic-style response
      (let ((anthropic-response (make-hash-table :test 'equal)))
        (puthash "content" (vconcat (nreverse content-items)) anthropic-response)
        (puthash "stop_reason"
                 (pcase finish-reason
                   ("tool_calls" "tool_use")
                   ("stop" "end_turn")
                   (_ finish-reason))
                 anthropic-response)
        anthropic-response))))

;;; Advice Functions for efrit-executor

(defun efrit-openrouter--api-request-advice (orig-fun request-data callback)
  "Around advice for OpenRouter API request transformation.
ORIG-FUN is the original function.
REQUEST-DATA is converted to OpenRouter format.
CALLBACK is wrapped to convert response back to Anthropic format."
  (if (eq efrit-api-backend 'openrouter)
      (let* ((converted-request (efrit-openrouter--convert-request request-data))
             (wrapped-callback
              (lambda (response)
                (funcall callback (efrit-openrouter--convert-response response)))))
        (funcall orig-fun converted-request wrapped-callback))
    (funcall orig-fun request-data callback)))

;;; Advice Functions for efrit-chat

(defvar efrit-openrouter--chat-original-model nil
  "Store original efrit-model value during chat request.")

(defun efrit-openrouter--chat-send-advice (orig-fun messages)
  "Around advice for efrit-chat OpenRouter support.
ORIG-FUN is efrit--send-api-request, MESSAGES is conversation history.
This rebuilds the entire request in OpenRouter format."
  (if (eq efrit-api-backend 'openrouter)
      (let* ((api-key (efrit-common-get-api-key))
             (url-request-method "POST")
             (url-request-extra-headers (efrit-common-build-headers api-key))
             ;; Get system prompt if tools enabled
             (system-prompt (when (bound-and-true-p efrit-enable-tools)
                              (efrit-tools-system-prompt)))
             ;; Format messages
             (formatted-messages
              (vconcat
               ;; System message first (OpenRouter style)
               (when system-prompt
                 `[(("role" . "system")
                    ("content" . ,system-prompt))])
               ;; User/assistant messages
               (mapcar (lambda (msg)
                         `(("role" . ,(alist-get 'role msg))
                           ("content" . ,(alist-get 'content msg))))
                       messages)))
             ;; Build OpenRouter request
             (request-data
              `(("model" . ,efrit-openrouter-model)
                ("max_tokens" . ,(or (bound-and-true-p efrit-max-tokens) 8192))
                ("temperature" . ,(or (bound-and-true-p efrit-temperature) 0.1))
                ("messages" . ,formatted-messages)
                ,@(when (bound-and-true-p efrit-enable-tools)
                    `(("tools" . ,(efrit-openrouter--convert-tools
                                   (efrit-openrouter--get-chat-tools)))))))
             (json-string (json-encode request-data))
             (escaped-json (efrit-common-escape-json-unicode json-string))
             (url-request-data (encode-coding-string escaped-json 'utf-8)))
        ;; Send request with OpenRouter response handler
        (url-retrieve (efrit-common-get-api-url)
                      #'efrit-openrouter--handle-chat-response nil t t))
    ;; Not OpenRouter, use original function
    (funcall orig-fun messages)))

(defun efrit-openrouter--get-chat-tools ()
  "Get efrit-chat tools in Anthropic format for conversion."
  '[(("name" . "eval_sexp")
     ("description" . "Evaluate a Lisp expression and return the result.")
     ("input_schema" . (("type" . "object")
                        ("properties" . (("expr" . (("type" . "string")
                                                    ("description" . "The Elisp expression to evaluate")))))
                        ("required" . ["expr"]))))
    (("name" . "get_context")
     ("description" . "Get context information about the Emacs environment")
     ("input_schema" . (("type" . "object")
                        ("properties" . (("request" . (("type" . "string")
                                                       ("description" . "Optional context request")))))
                        ("required" . []))))
    (("name" . "resolve_path")
     ("description" . "Resolve a path from natural language description")
     ("input_schema" . (("type" . "object")
                        ("properties" . (("path_description" . (("type" . "string")
                                                                ("description" . "Natural language path description")))))
                        ("required" . ["path_description"]))))])

(defun efrit-openrouter--handle-chat-response (status)
  "Handle OpenRouter response for efrit-chat.
STATUS is the url-retrieve status.
Converts OpenRouter response to Anthropic format and calls original handler."
  (if (plist-get status :error)
      ;; Error handling
      (progn
        (message "OpenRouter API error: %s" (plist-get status :error))
        (when (buffer-live-p (current-buffer))
          (kill-buffer (current-buffer))))
    ;; Parse and convert response
    (goto-char (point-min))
    (when (re-search-forward "\n\n" nil t)
      (let* ((json-object-type 'hash-table)
             (json-array-type 'vector)
             (json-key-type 'string)
             (response (condition-case nil
                           (json-read)
                         (error nil)))
             (converted (when response
                          (efrit-openrouter--convert-response response))))
        ;; Call original efrit-chat handler with converted response
        (when converted
          (efrit--handle-api-response-with-data status converted))))
    (when (buffer-live-p (current-buffer))
      (kill-buffer (current-buffer)))))

(defun efrit--handle-api-response-with-data (_status response-data)
  "Process converted RESPONSE-DATA for efrit-chat.
_STATUS is ignored (already processed)."
  (when response-data
    (let* ((content (gethash "content" response-data))
           (_stop-reason (gethash "stop_reason" response-data)))
      ;; Extract text and tool calls
      (with-current-buffer (get-buffer-create "*efrit-chat*")
        (let ((inhibit-read-only t)
              (text-parts '())
              (tool-calls '()))
          ;; Process content items
          (when (vectorp content)
            (dotimes (i (length content))
              (let* ((item (aref content i))
                     (type (cdr (assoc "type" item))))
                (cond
                 ((string= type "text")
                  (push (cdr (assoc "text" item)) text-parts))
                 ((string= type "tool_use")
                  (push item tool-calls))))))
          ;; Display text
          (when text-parts
            (goto-char (point-max))
            (insert "\n\nAssistant: " (string-join (nreverse text-parts) "\n"))
            (insert "\n"))
          ;; Handle tool calls if any
          (when tool-calls
            (dolist (tool (nreverse tool-calls))
              (let* ((name (cdr (assoc "name" tool)))
                     (input (cdr (assoc "input" tool)))
                     (expr (cdr (assoc "expr" input))))
                (when (and (string= name "eval_sexp") expr)
                  (insert (format "\n[Executing: %s]\n" expr))
                  (condition-case err
                      (let ((result (eval (read expr))))
                        (insert (format "Result: %S\n" result)))
                    (error
                     (insert (format "Error: %s\n" (error-message-string err))))))))))))))

;;; Activation

(defun efrit-openrouter-enable ()
  "Enable OpenRouter support via advice."
  (interactive)
  ;; For efrit-executor (efrit-do)
  (advice-add 'efrit-executor--api-request :around
              #'efrit-openrouter--api-request-advice)
  ;; For efrit-chat
  (advice-add 'efrit--send-api-request :around
              #'efrit-openrouter--chat-send-advice)
  (message "Efrit OpenRouter support enabled (executor + chat)"))

(defun efrit-openrouter-disable ()
  "Disable OpenRouter support."
  (interactive)
  (advice-remove 'efrit-executor--api-request
                 #'efrit-openrouter--api-request-advice)
  (advice-remove 'efrit--send-api-request
                 #'efrit-openrouter--chat-send-advice)
  (message "Efrit OpenRouter support disabled"))

;; Auto-enable when loaded
(efrit-openrouter-enable)

(provide 'efrit-openrouter)

;;; efrit-openrouter.el ends here
