/*
Copyright 2024.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// MyDatabaseSpec defines the desired state of MyDatabase
type MyDatabaseSpec struct {
	// Engine is the database engine type (postgres, mysql, redis)
	// +kubebuilder:validation:Enum=postgres;mysql;redis
	// +kubebuilder:validation:Required
	Engine string `json:"engine"`

	// Version is the database engine version
	// +kubebuilder:validation:Required
	Version string `json:"version"`

	// StorageSize is the size of the persistent volume (e.g., "10Gi")
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^\d+Gi$`
	StorageSize string `json:"storageSize"`

	// Replicas is the number of database pod replicas
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=5
	// +kubebuilder:default=1
	Replicas int32 `json:"replicas,omitempty"`

	// StorageClass is the Kubernetes StorageClass to use for the PVC
	// +optional
	StorageClass string `json:"storageClass,omitempty"`

	// Resources defines CPU and memory requests/limits for the database pod
	// +optional
	Resources *DatabaseResources `json:"resources,omitempty"`

	// BackupEnabled enables automatic daily backups
	// +kubebuilder:default=false
	BackupEnabled bool `json:"backupEnabled,omitempty"`
}

// DatabaseResources defines resource requests and limits
type DatabaseResources struct {
	// CPURequest is the CPU request (e.g., "250m")
	CPURequest string `json:"cpuRequest,omitempty"`
	// CPULimit is the CPU limit (e.g., "1")
	CPULimit string `json:"cpuLimit,omitempty"`
	// MemoryRequest is the memory request (e.g., "256Mi")
	MemoryRequest string `json:"memoryRequest,omitempty"`
	// MemoryLimit is the memory limit (e.g., "1Gi")
	MemoryLimit string `json:"memoryLimit,omitempty"`
}

// MyDatabaseStatus defines the observed state of MyDatabase
type MyDatabaseStatus struct {
	// Phase represents the current lifecycle phase of the database
	// +kubebuilder:validation:Enum=Provisioning;Running;Failed;Terminating
	Phase string `json:"phase,omitempty"`

	// ReadyReplicas is the number of ready database pod replicas
	ReadyReplicas int32 `json:"readyReplicas,omitempty"`

	// StorageProvisioned indicates whether the PVC has been bound
	StorageProvisioned bool `json:"storageProvisioned,omitempty"`

	// Endpoint is the service endpoint for connecting to the database
	Endpoint string `json:"endpoint,omitempty"`

	// LastReconcileTime is the timestamp of the last successful reconciliation
	LastReconcileTime *metav1.Time `json:"lastReconcileTime,omitempty"`

	// Conditions represent the latest available observations of the database state
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Engine",type=string,JSONPath=`.spec.engine`
// +kubebuilder:printcolumn:name="Version",type=string,JSONPath=`.spec.version`
// +kubebuilder:printcolumn:name="Storage",type=string,JSONPath=`.spec.storageSize`
// +kubebuilder:printcolumn:name="Replicas",type=integer,JSONPath=`.spec.replicas`
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`
// +kubebuilder:resource:shortName=mydb

// MyDatabase is the Schema for the mydatabases API
type MyDatabase struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   MyDatabaseSpec   `json:"spec,omitempty"`
	Status MyDatabaseStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// MyDatabaseList contains a list of MyDatabase
type MyDatabaseList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []MyDatabase `json:"items"`
}

func init() {
	SchemeBuilder.Register(&MyDatabase{}, &MyDatabaseList{})
}
