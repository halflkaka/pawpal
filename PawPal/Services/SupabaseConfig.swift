import Foundation
import Supabase

enum SupabaseConfig {
    static let urlString = "https://acxtboxjturbqloovyyg.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFjeHRib3hqdHVyYnFsb292eXlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU2MTg2NDYsImV4cCI6MjA5MTE5NDY0Nn0.DbtLVjBtDK0JHsOU88OrYxTZsegogiWw_Qe3Yx5B-QY"

    /// Single shared client — auth session is stored here and shared by all
    /// services so RLS policies that check auth.uid() work correctly.
    static let client: SupabaseClient = {
        guard let url = URL(string: urlString) else {
            fatalError("Invalid Supabase URL")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }()
}
