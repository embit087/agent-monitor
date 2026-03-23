use tokio::sync::broadcast;

#[derive(Clone)]
pub struct BrowserHub {
    sender: broadcast::Sender<String>,
}

impl BrowserHub {
    pub fn new(capacity: usize) -> Self {
        let (sender, _) = broadcast::channel(capacity);
        Self { sender }
    }

    pub fn broadcast(&self, msg: &str) {
        // Ignore error if no subscribers
        let _ = self.sender.send(msg.to_string());
    }

    pub fn subscribe(&self) -> broadcast::Receiver<String> {
        self.sender.subscribe()
    }
}
