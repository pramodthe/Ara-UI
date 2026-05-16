//
//  ImageGenerationView.swift
//  nova
//
//  View for generating images from screen clips
//

import SwiftUI

struct ImageGenerationView: View {
    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var clipImageExists: Bool = false
    
    private let workspaceURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/AraUI")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Image Generation")
                .font(.headline)
            
            if !clipImageExists {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No clip.png found. Use Option+C to capture a screen region first.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $prompt)
                    .frame(height: 80)
                    .font(.system(size: 13))
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .disabled(isGenerating || !clipImageExists)
                
                if prompt.isEmpty && !isGenerating {
                    Text("e.g., 'Add a rainbow effect to this image'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, -4)
                }
            }
            
            Button(action: generateImage) {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 4)
                    }
                    Text(isGenerating ? "Generating..." : "Create")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(prompt.isEmpty || isGenerating || !clipImageExists)
            
            if let error = errorMessage {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
            
            if let success = successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(success)
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            checkClipImageExists()
        }
        .onChange(of: clipImageExists) { _ in
            // Reset messages when clip image status changes
            errorMessage = nil
            successMessage = nil
        }
    }
    
    private func checkClipImageExists() {
        let clipPath = workspaceURL.appendingPathComponent("clip.png").path
        clipImageExists = FileManager.default.fileExists(atPath: clipPath)
    }
    
    private func generateImage() {
        errorMessage = nil
        successMessage = nil
        isGenerating = true
        
        Task {
            do {
                let clipPath = workspaceURL.appendingPathComponent("clip.png").path
                let imageData = try await ImageGenerationService.shared.generateImage(
                    fromImagePath: clipPath,
                    prompt: prompt
                )
                
                // Save the generated image
                let nanoPath = workspaceURL.appendingPathComponent("nano.png")
                try imageData.write(to: nanoPath)
                
                // Open the image automatically
                NSWorkspace.shared.open(nanoPath)
                
                await MainActor.run {
                    isGenerating = false
                    successMessage = "Image saved as nano.png"
                    
                    // Clear success message after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        successMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct ImageGenerationView_Previews: PreviewProvider {
    static var previews: some View {
        ImageGenerationView()
    }
}
