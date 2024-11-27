/*
Copyright 2024 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// +genclient
// +genclient:nonNamespaced
// +kubebuilder:object:root=true
// +kubebuilder:resource:categories=network,shortName=pnw
// +kubebuilder:subresource:status
// +kubebuilder:resource:scope=Cluster
// +kubebuilder:storageversion
// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`

// PodNetwork represent a logical network on the k8s cluster.
type PodNetwork struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PodNetworkSpec   `json:"spec"`
	Status PodNetworkStatus `json:"status,omitempty"`
}

// NetworkSpec contains the specifications for network object
type PodNetworkSpec struct {
	// Enabled is used to administratively enable/disable a PodNetwork.
	// When set to false, PodNetwork Ready condition will be set to False.
	// Defaults to True.
	//
	// +kubebuilder:default=true
	Enabled bool `json:"enabled"`

	// DeviceClassName is the name of DRA class to use.
	//
	// +optional
	DeviceClassName string `json:"deviceClassName,omitempty"`
}

// PodNetworkStatus contains the status information related to the network.
type PodNetworkStatus struct {
	// Conditions describe the current conditions of the PodNetwork.
	//
	// Known condition types are:
	//
	// * "Accepted"
	// * "Ready"
	//
	// +optional
	// +listType=map
	// +listMapKey=type
	// +kubebuilder:validation:MaxItems=8
	// +kubebuilder:default={{type: "Accepted", status: "Unknown", reason:"Pending", message:"Waiting for controller", lastTransitionTime: "1970-01-01T00:00:00Z"}}
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +genclient
// +genclient:nonNamespaced
// +genclient:onlyVerbs=get
// +kubebuilder:object:root=true
// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object

// PodNetworkList contains a list of PodNetwork resources.
type PodNetworkList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`

	// Items is a slice of Network resources.
	Items []PodNetwork `json:"items"`
}
