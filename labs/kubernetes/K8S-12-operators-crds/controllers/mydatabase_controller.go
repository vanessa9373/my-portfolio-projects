/*
Copyright 2024.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
*/

package controllers

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	databasev1alpha1 "github.com/example/mydatabase-operator/api/v1alpha1"
)

const (
	finalizerName = "database.example.com/finalizer"
)

// MyDatabaseReconciler reconciles a MyDatabase object
type MyDatabaseReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=database.example.com,resources=mydatabases,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=database.example.com,resources=mydatabases/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=database.example.com,resources=mydatabases/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=persistentvolumeclaims,verbs=get;list;watch;create;update;patch;delete

// Reconcile is the main reconciliation loop for MyDatabase resources
func (r *MyDatabaseReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// Fetch the MyDatabase resource
	mydb := &databasev1alpha1.MyDatabase{}
	if err := r.Get(ctx, req.NamespacedName, mydb); err != nil {
		if errors.IsNotFound(err) {
			logger.Info("MyDatabase resource not found, likely deleted")
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	// Handle deletion with Finalizer
	if mydb.ObjectMeta.DeletionTimestamp.IsZero() {
		// Resource is not being deleted - add finalizer if not present
		if !controllerutil.ContainsFinalizer(mydb, finalizerName) {
			controllerutil.AddFinalizer(mydb, finalizerName)
			if err := r.Update(ctx, mydb); err != nil {
				return ctrl.Result{}, err
			}
		}
	} else {
		// Resource is being deleted - run cleanup
		if controllerutil.ContainsFinalizer(mydb, finalizerName) {
			logger.Info("Running finalizer cleanup", "name", mydb.Name)

			// Update status to Terminating
			mydb.Status.Phase = "Terminating"
			_ = r.Status().Update(ctx, mydb)

			// Delete PVC (not garbage collected by owner reference)
			pvc := &corev1.PersistentVolumeClaim{}
			pvcName := types.NamespacedName{Name: mydb.Name + "-data", Namespace: mydb.Namespace}
			if err := r.Get(ctx, pvcName, pvc); err == nil {
				logger.Info("Deleting PVC", "pvc", pvcName)
				if err := r.Delete(ctx, pvc); err != nil {
					return ctrl.Result{}, err
				}
			}

			// Remove finalizer to allow deletion
			controllerutil.RemoveFinalizer(mydb, finalizerName)
			if err := r.Update(ctx, mydb); err != nil {
				return ctrl.Result{}, err
			}
		}
		return ctrl.Result{}, nil
	}

	// Update status to Provisioning
	if mydb.Status.Phase == "" {
		mydb.Status.Phase = "Provisioning"
		if err := r.Status().Update(ctx, mydb); err != nil {
			return ctrl.Result{}, err
		}
	}

	// Reconcile PVC
	if err := r.reconcilePVC(ctx, mydb); err != nil {
		logger.Error(err, "Failed to reconcile PVC")
		mydb.Status.Phase = "Failed"
		_ = r.Status().Update(ctx, mydb)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, err
	}

	// Reconcile Deployment
	if err := r.reconcileDeployment(ctx, mydb); err != nil {
		logger.Error(err, "Failed to reconcile Deployment")
		mydb.Status.Phase = "Failed"
		_ = r.Status().Update(ctx, mydb)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, err
	}

	// Reconcile Service
	if err := r.reconcileService(ctx, mydb); err != nil {
		logger.Error(err, "Failed to reconcile Service")
		mydb.Status.Phase = "Failed"
		_ = r.Status().Update(ctx, mydb)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, err
	}

	// Update status to Running
	now := metav1.Now()
	mydb.Status.Phase = "Running"
	mydb.Status.Endpoint = fmt.Sprintf("%s.%s.svc.cluster.local", mydb.Name, mydb.Namespace)
	mydb.Status.StorageProvisioned = true
	mydb.Status.LastReconcileTime = &now
	if err := r.Status().Update(ctx, mydb); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("Reconciliation complete", "name", mydb.Name, "phase", mydb.Status.Phase)
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

// reconcilePVC creates or updates the PersistentVolumeClaim
func (r *MyDatabaseReconciler) reconcilePVC(ctx context.Context, mydb *databasev1alpha1.MyDatabase) error {
	pvc := &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      mydb.Name + "-data",
			Namespace: mydb.Namespace,
			Labels: map[string]string{
				"app":        mydb.Name,
				"managed-by": "mydatabase-operator",
			},
		},
		Spec: corev1.PersistentVolumeClaimSpec{
			AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce},
			Resources: corev1.VolumeResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceStorage: resource.MustParse(mydb.Spec.StorageSize),
				},
			},
		},
	}

	// Set owner reference (note: PVC also cleaned up by finalizer for safety)
	if err := ctrl.SetControllerReference(mydb, pvc, r.Scheme); err != nil {
		return err
	}

	existing := &corev1.PersistentVolumeClaim{}
	err := r.Get(ctx, types.NamespacedName{Name: pvc.Name, Namespace: pvc.Namespace}, existing)
	if errors.IsNotFound(err) {
		return r.Create(ctx, pvc)
	}
	return err
}

// reconcileDeployment creates or updates the database Deployment
func (r *MyDatabaseReconciler) reconcileDeployment(ctx context.Context, mydb *databasev1alpha1.MyDatabase) error {
	image := getImageForEngine(mydb.Spec.Engine, mydb.Spec.Version)
	port := getPortForEngine(mydb.Spec.Engine)

	deploy := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      mydb.Name,
			Namespace: mydb.Namespace,
			Labels: map[string]string{
				"app":        mydb.Name,
				"managed-by": "mydatabase-operator",
			},
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &mydb.Spec.Replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: map[string]string{"app": mydb.Name},
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{
						"app":        mydb.Name,
						"managed-by": "mydatabase-operator",
					},
				},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{
						{
							Name:  mydb.Spec.Engine,
							Image: image,
							Ports: []corev1.ContainerPort{{ContainerPort: port}},
							Resources: corev1.ResourceRequirements{
								Requests: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("250m"),
									corev1.ResourceMemory: resource.MustParse("256Mi"),
								},
								Limits: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("1"),
									corev1.ResourceMemory: resource.MustParse("1Gi"),
								},
							},
							VolumeMounts: []corev1.VolumeMount{
								{Name: "data", MountPath: "/data"},
							},
						},
					},
					Volumes: []corev1.Volume{
						{
							Name: "data",
							VolumeSource: corev1.VolumeSource{
								PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
									ClaimName: mydb.Name + "-data",
								},
							},
						},
					},
				},
			},
		},
	}

	if err := ctrl.SetControllerReference(mydb, deploy, r.Scheme); err != nil {
		return err
	}

	existing := &appsv1.Deployment{}
	err := r.Get(ctx, types.NamespacedName{Name: deploy.Name, Namespace: deploy.Namespace}, existing)
	if errors.IsNotFound(err) {
		return r.Create(ctx, deploy)
	}
	if err != nil {
		return err
	}

	// Update existing deployment
	existing.Spec.Replicas = deploy.Spec.Replicas
	existing.Spec.Template = deploy.Spec.Template
	return r.Update(ctx, existing)
}

// reconcileService creates or updates the database Service
func (r *MyDatabaseReconciler) reconcileService(ctx context.Context, mydb *databasev1alpha1.MyDatabase) error {
	port := getPortForEngine(mydb.Spec.Engine)

	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      mydb.Name,
			Namespace: mydb.Namespace,
			Labels: map[string]string{
				"app":        mydb.Name,
				"managed-by": "mydatabase-operator",
			},
		},
		Spec: corev1.ServiceSpec{
			Selector: map[string]string{"app": mydb.Name},
			Ports: []corev1.ServicePort{
				{Port: port, TargetPort: intstr(port)},
			},
			Type: corev1.ServiceTypeClusterIP,
		},
	}

	if err := ctrl.SetControllerReference(mydb, svc, r.Scheme); err != nil {
		return err
	}

	existing := &corev1.Service{}
	err := r.Get(ctx, types.NamespacedName{Name: svc.Name, Namespace: svc.Namespace}, existing)
	if errors.IsNotFound(err) {
		return r.Create(ctx, svc)
	}
	return err
}

// Helper functions
func getImageForEngine(engine, version string) string {
	switch engine {
	case "postgres":
		return fmt.Sprintf("postgres:%s-alpine", version)
	case "mysql":
		return fmt.Sprintf("mysql:%s", version)
	case "redis":
		return fmt.Sprintf("redis:%s-alpine", version)
	default:
		return fmt.Sprintf("postgres:%s-alpine", version)
	}
}

func getPortForEngine(engine string) int32 {
	switch engine {
	case "postgres":
		return 5432
	case "mysql":
		return 3306
	case "redis":
		return 6379
	default:
		return 5432
	}
}

// SetupWithManager sets up the controller with the Manager
func (r *MyDatabaseReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&databasev1alpha1.MyDatabase{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Owns(&corev1.PersistentVolumeClaim{}).
		Complete(r)
}
