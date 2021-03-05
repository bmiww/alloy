#|
 This file is a part of Alloy
 (c) 2019 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.alloy.layouts.constraint)

(defun make-variables (element solver &key (strength :medium))
  (list (cass:make-variable solver :name (format NIL "X ~a" element) :strength strength)
        (cass:make-variable solver :name (format NIL "Y ~a" element) :strength strength)
        (cass:make-variable solver :name (format NIL "W ~a" element) :strength strength)
        (cass:make-variable solver :name (format NIL "H ~a" element) :strength strength)))

(defclass layout (alloy:layout alloy:layout-element alloy:vector-container)
  ((solver :initform (cass:make-solver) :reader solver)
   (variables :initform (make-hash-table :test 'eq) :reader variables)
   (constraints :initform (make-hash-table :test 'eq) :reader constraints)))

(defmethod initialize-instance ((layout layout) &key)
  (call-next-method)
  (setf (gethash layout (variables layout))
        (make-variables layout (solver layout) :strength :strong)))

(defun suggest-extent (layout element extent)
  (with-vars (x y w h layout) element
    (cass:suggest x (alloy:to-un (alloy:extent-x extent)))
    (cass:suggest y (alloy:to-un (alloy:extent-y extent)))
    (cass:suggest w (alloy:to-un (alloy:extent-w extent)))
    (cass:suggest h (alloy:to-un (alloy:extent-h extent)))
    (cass:update-variables (solver layout))))

(defun element-var (layout element var)
  (with-vars (x y w h layout) element
    (ecase var
      (:x x)
      (:y y)
      (:w w)
      (:h h))))

(defun suggest (layout element var size)
  (alloy:with-unit-parent layout
    (cass:suggest (element-var layout element var) (alloy:to-un size))
    (cass:update-variables (solver layout))
    (alloy:do-elements (element layout)
      (update layout element))))

(defun constrain (layout element var value &key (strength :required))
  (alloy:with-unit-parent layout
    (prog1 (cass:constrain-with (solver layout) `(= ,(element-var layout element var) ,(alloy:to-un value)) :strength strength)
      (cass:update-variables (solver layout))
      (alloy:do-elements (element layout)
        (update layout element)))))

(defun update (layout element)
  (with-vars (x y w h layout) element
    (setf (alloy:bounds element)
          (alloy:px-extent (alloy:un (cass:value x)) (alloy:un (cass:value y))
                           (alloy:un (cass:value w)) (alloy:un (cass:value h))))))

(defmethod alloy:enter ((element alloy:layout-element) (layout layout) &key constraints)
  (call-next-method)
  (setf (gethash element (variables layout))
        (make-variables element (solver layout)))
  (apply-constraints constraints element layout))

(defmethod alloy:leave :after ((element alloy:layout-element) (layout layout))
  (remhash element (variables layout)))

(defmethod alloy:update ((element alloy:layout-element) (layout layout) &key constraints clear)
  (when clear
    (dolist (constraint (gethash element (constraints layout)))
      (cass:delete-constraint constraint)))
  (apply-constraints constraints element layout))

(defmethod alloy:notice-bounds ((element alloy:layout-element) (layout layout)))

(defmethod (setf alloy:bounds) :after (extent (layout layout))
  (alloy:with-unit-parent layout
    (suggest-extent layout layout extent)
    (alloy:do-elements (element layout)
      (update layout element))))

(defmethod alloy:suggest-bounds (extent (layout layout))
  (alloy:with-unit-parent layout
    (suggest-extent layout layout extent)
    (with-vars (x y w h layout) layout
      (alloy:extent (cass:value x) (cass:value y)
                    (cass:value w) (cass:value h)))))

(defun apply-constraints (constraints element layout)
  (dolist (expression constraints layout)
    (multiple-value-bind (expressions strength) (transform-expression expression)
      (dolist (expression expressions)
        (push (cass:constrain-with (solver layout) (rewrite-expression expression element layout) :strength (or strength :strong))
              (gethash element (constraints layout)))))))
