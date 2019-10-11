#|
 This file is a part of Alloy
 (c) 2019 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.alloy.renderers.glfw)

(defvar *window-map* (make-hash-table :test 'eq))

(cffi:defcstruct %glfw::image
  (%glfw::width :int)
  (%glfw::height :int)
  (%glfw::pixels :pointer))

(cffi:defcfun (%glfw::set-window-icon "glfwSetWindowIcon") :void
  (window :pointer)
  (count :int)
  (images :pointer))

(cffi:defcfun (%glfw::set-cursor-icon "glfwCreateCursor") :void
  (image :pointer)
  (xhot :int)
  (yhot :int))

(cffi:defcfun (%glfw::destroy-cursor "glfwDestroyCursor") :void
  (cursor :pointer))

(cffi:defcfun (%glfw::set-cursor "glfwSetCursor") :void
  (window :pointer)
  (cursor :pointer))

(cffi:defcfun (%glfw::request-window-attention "glfwRequestWindowAttention") :void
  (window :pointer))

(cffi:defcfun (%glfw::focus-window "glfwFocusWindow") :void
  (window :pointer))

(cffi:defcfun (%glfw::maximize-window "glfwMaximizeWindow") :void
  (window :pointer))

(cffi:defcfun (%glfw::set-window-attrib "glfwSetWindowAttrib") :void
  (window :pointer)
  (attrib %glfw::window-hint)
  (value :boolean))

(defclass icon (window:icon simple:image)
  ())

(defclass renderer (alloy:renderer)
  ((parent :initarg :parent :accessor parent)
   (pointer :accessor pointer)))

(defmethod make-instance ((renderer renderer) &key parent title size monitor visible-p decorated-p)
  (let ((window (cl-glfw3:create-window
                 :width (alloy:pxw size)
                 :height (alloy:pxh size)
                 :title title
                 :monitor (if monitor
                              (pointer monitor)
                              (cffi:null-pointer))
                 :visible visible-p
                 :decorated decorated-p
                 :opengl-forward-compat T
                 :opengl-profile :core
                 :context-version-major 3
                 :context-versoin-minor 3
                 :shared (if (slot-boundp renderer 'parent)
                             (pointer (parent renderer))
                             (cffi:null-pointer)))))
    (setf (gethash (cffi:pointer-address window) *window-map*) renderer)
    (setf (pointer renderer) window)))

(defmethod alloy:allocate ((renderer renderer)))

(defmethod alloy:deallocate ((renderer renderer))
  (cl-glfw3:destroy-window (pointer renderer))
  (remhash (pointer renderer) *window-map*)
  (slot-makunbound renderer 'pointer))

(defmethod window:make-icon ((renderer renderer) size pixel-data)
  (make-instance 'icon :size size :data pixel-data))