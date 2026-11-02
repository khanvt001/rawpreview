//
//  DevelopKernels.swift
//  rawpreview
//

import CoreImage
import Foundation

/// The Core Image kernels compiled from DevelopKernels.metal into the app's
/// default Metal library.
nonisolated enum DevelopKernels {
    private static let library: Data? = Bundle.main.url(forResource: "default", withExtension: "metallib")
        .flatMap { try? Data(contentsOf: $0) }

    static func color(_ name: String) -> CIColorKernel? {
        library.flatMap { try? CIColorKernel(functionName: name, fromMetalLibraryData: $0) }
    }

    static func general(_ name: String) -> CIKernel? {
        library.flatMap { try? CIKernel(functionName: name, fromMetalLibraryData: $0) }
    }
}
