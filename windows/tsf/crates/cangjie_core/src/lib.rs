//! 倉頡學習版輸入核心：cjlearn（Python）的逐段移植。純邏輯，不依賴 Windows API。
pub mod composer;
pub mod model;
pub mod settings;

pub use composer::{Composer, KeyResult};
pub use model::{Candidate, Model};
