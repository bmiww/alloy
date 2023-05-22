#|
 This file is a part of Alloy
 (c) 2019 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.alloy.renderers.opengl)

(defmethod view-size ((renderer renderer))
  (let ((data (gl:get-integer :viewport 4)))
    (alloy:px-size (aref data 2) (aref data 3))))

(defstruct (gl-resource (:copier NIL) (:predicate NIL))
  (name 0 :type (unsigned-byte 32)))

(defmethod gl-name ((resource gl-resource))
  (gl-resource-name resource))

(defstruct (vbo (:constructor make-vbo (name type)) (:include gl-resource) (:copier NIL) (:predicate NIL))
  (type :array-buffer))

(defstruct (vao (:constructor make-vao (name type)) (:include gl-resource) (:copier NIL) (:predicate NIL))
  (type :arrays))

(defstruct (fbo (:constructor make-fbo (name color depth)) (:include gl-resource) (:copier NIL) (:predicate NIL))
  (color 0 :type (unsigned-byte 32))
  (depth 0 :type (unsigned-byte 32))
  (width 0 :type (unsigned-byte 32))
  (height 0 :type (unsigned-byte 32)))

(defstruct (program (:constructor make-program (name)) (:include gl-resource) (:copier NIL) (:predicate NIL)))

(defmethod bind ((program program))
  (gl:use-program (gl-resource-name program)))

(defstruct (texture (:constructor make-tex (name)) (:include gl-resource) (:copier NIL) (:predicate NIL)))

(defmethod bind ((texture texture))
  (gl:active-texture :texture0)
  (gl:bind-texture :texture-2d (gl-resource-name texture)))

(defmethod make-shader ((renderer renderer) &key vertex-shader fragment-shader)
  (let ((vert (gl:create-shader :vertex-shader))
        (frag (gl:create-shader :fragment-shader))
        (prog (gl:create-program)))
    (flet ((make (name source)
             (gl:shader-source name (format NIL "#version 330 core~%~a" source))
             (gl:compile-shader name)
             (unless (gl:get-shader name :compile-status)
               (error "Failed to compile: ~%~a~%Shader source:~%~a"
                      (gl:get-shader-info-log name) source))))
      (make vert vertex-shader)
      (make frag fragment-shader)
      (gl:attach-shader prog vert)
      (gl:attach-shader prog frag)
      (gl:link-program prog)
      (gl:detach-shader prog vert)
      (gl:detach-shader prog frag)
      (unless (gl:get-program prog :link-status)
        (error "Failed to link: ~%~a"
               (gl:get-program-info-log prog)))
      (make-program prog))))

(defmethod (setf uniform) (value (program program) uniform)
  (let ((location (gl:get-uniform-location (gl-resource-name program) uniform)))
    (etypecase value
      (vector
       (cffi:with-pointer-to-vector-data (data value)
         (%gl:uniform-matrix-3fv location 1 T data)))
      (single-float
       (%gl:uniform-1f location value))
      ((unsigned-byte 32)
       (%gl:uniform-1i location value))
      (colored:color
       (%gl:uniform-4f location (colored:r value) (colored:g value) (colored:b value) (colored:a value)))
      (alloy:point
       (%gl:uniform-2f location (alloy:pxx value) (alloy:pxy value)))
      (alloy:size
       (%gl:uniform-2f location (alloy:pxw value) (alloy:pxh value)))))
  value)

(defmethod make-vertex-buffer ((renderer renderer) (contents vector) &key (buffer-type :array-buffer) data-usage)
  (let ((name (gl:gen-buffer)))
    (gl:bind-buffer buffer-type name)
    (cffi:with-pointer-to-vector-data (data contents)
      (%gl:buffer-data buffer-type (* (length contents) 4) data data-usage))
    (gl:bind-buffer buffer-type 0)
    (make-vbo name buffer-type)))

(defmethod make-vertex-buffer ((renderer renderer) (size integer) &key (buffer-type :array-buffer) data-usage)
  (let ((name (gl:gen-buffer)))
    (gl:bind-buffer buffer-type name)
    (%gl:buffer-data buffer-type (* size 4) (cffi:null-pointer) data-usage)
    (gl:bind-buffer buffer-type 0)
    (make-vbo name buffer-type)))

(defmethod update-vertex-buffer ((buffer vbo) contents)
  (gl:bind-buffer (vbo-type buffer) (gl-resource-name buffer))
  (cffi:with-pointer-to-vector-data (data contents)
    (%gl:buffer-data (vbo-type buffer) (* (length contents) 4) data :stream-draw))
  (gl:bind-buffer (vbo-type buffer) 0)
  buffer)

(defmethod make-vertex-array ((renderer renderer) bindings &key index-buffer)
  (let ((name (gl:gen-vertex-array))
        (type :arrays)
        (i 0))
    (gl:bind-vertex-array name)
    (dolist (binding bindings)
      (destructuring-bind (buffer &key (size 3) (stride 0) (offset 0)) binding
        (gl:bind-buffer :array-buffer (gl-resource-name buffer))
        (gl:vertex-attrib-pointer i size :float NIL stride offset)
        (gl:enable-vertex-attrib-array i)
        (incf i)))
    (when index-buffer
      (gl:bind-buffer :element-array-buffer (gl-resource-name index-buffer))
      (setf type :elements))
    (gl:bind-vertex-array 0)
    (make-vao name type)))

(defmethod draw-vertex-array ((array vao) primitive-type offset count)
  (gl:bind-vertex-array (gl-resource-name array))
  (ecase (vao-type array)
    (:arrays (%gl:draw-arrays primitive-type offset count))
    (:elements (%gl:draw-elements primitive-type count :unsigned-int offset)))
  (gl:bind-vertex-array 0)
  array)

(defmethod make-texture ((renderer renderer) width height data &key (channels 4) (filtering :linear))
  (let* ((format (ecase channels (1 :red) (2 :rg) (3 :rgb) (4 :rgba)))
         (name (gl:gen-texture)))
    (gl:bind-texture :texture-2d name)
    (flet ((swizzle (&rest channels)
             (cffi:with-foreign-object (params :int 4)
               (loop for c in channels
                     for i from 0
                     do (setf (cffi:mem-aref params :int i)
                              (ecase c
                                (:r (cffi:foreign-enum-value '%gl:enum :red))
                                (:g (cffi:foreign-enum-value '%gl:enum :green))
                                (:b (cffi:foreign-enum-value '%gl:enum :blue))
                                (:a (cffi:foreign-enum-value '%gl:enum :alpha))
                                (1  (cffi:foreign-enum-value '%gl:enum :one)))))
               (%gl:tex-parameter-iv :texture-2d :texture-swizzle-rgba params))))
      (ecase format
        (:red (swizzle :r :r :r 1))
        (:rg (swizzle :r :r :r :g))
        (:rgb (swizzle :r :g :b 1))
        (:rgba (swizzle :r :g :b :a))))
    (gl:tex-image-2d :texture-2d 0 format width height 0 format :unsigned-byte data)
    (gl:tex-parameter :texture-2d :texture-wrap-s :clamp-to-border)
    (gl:tex-parameter :texture-2d :texture-wrap-t :clamp-to-border)
    (gl:tex-parameter :texture-2d :texture-min-filter filtering)
    (gl:tex-parameter :texture-2d :texture-mag-filter filtering)
    (gl:bind-texture :texture-2d 0)
    (make-tex name)))

(defmethod make-framebuffer ((renderer renderer))
  (let* ((color (gl:gen-texture))
         (depth (gl:gen-texture))
         (buffer (gl:gen-framebuffer))
         (fbo (make-fbo buffer color depth)))
    (let ((data (gl:get-integer :viewport 4)))
      (resize fbo (aref data 2) (aref data 3)))
    (gl:bind-framebuffer :framebuffer buffer)
    (%gl:framebuffer-texture :framebuffer :color-attachment0 color 0)
    (%gl:framebuffer-texture :framebuffer :depth-stencil-attachment depth 0)
    (gl:draw-buffers '(:color-attachment0))
    (gl:bind-framebuffer :framebuffer 0)
    fbo))

(defmethod resize ((fbo fbo) w h)
  (when (or (/= w (fbo-width fbo))
            (/= h (fbo-height fbo)))
    (let ((tex (gl:get-integer :texture-binding-2d)))
      (gl:bind-texture :texture-2d (fbo-color fbo))
      (gl:tex-image-2d :texture-2d 0 :rgba w h 0 :rgba :unsigned-byte (cffi:null-pointer))
      (gl:bind-texture :texture-2d (fbo-depth fbo))
      (gl:tex-image-2d :texture-2d 0 :depth-stencil w h 0 :depth-stencil :unsigned-byte (cffi:null-pointer))
      (gl:bind-texture :texture-2d tex)
      (setf (fbo-width fbo) w)
      (setf (fbo-height fbo) h))))

(defmethod bind ((fbo fbo))
  ;; Check for size consistency now
  (let ((data (gl:get-integer :viewport 4)))
    (resize fbo (aref data 2) (aref data 3)))
  (gl:bind-framebuffer :draw-framebuffer (gl-resource-name fbo))
  (gl:clear :color-buffer :depth-buffer :stencil-buffer))

(defmethod blit-framebuffer ((fbo fbo))
  (gl:bind-framebuffer :read-framebuffer (gl-resource-name fbo))
  (gl:bind-framebuffer :draw-framebuffer 0)
  (let ((w (fbo-width fbo))
        (h (fbo-height fbo)))
    (%gl:blit-framebuffer 0 0 w h 0 0 w h '(:color-buffer :depth-buffer :stencil-buffer) :nearest)))
