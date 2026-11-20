document.addEventListener("DOMContentLoaded", () => {
  const form = document.getElementById("contact-form");
  if (!form) return;

  const statusBox = document.getElementById("form-status");

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    statusBox.className = "status-msg";
    statusBox.textContent = "";

    const payload = {
      name: form.name.value.trim(),
      email: form.email.value.trim(),
      message: form.message.value.trim(),
    };

    try {
      const response = await fetch("/api/contact", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        throw new Error(`Server responded with ${response.status}`);
      }

      statusBox.className = "status-msg ok";
      statusBox.textContent = "Thank you, your message has been received.";
      form.reset();
    } catch (err) {
      statusBox.className = "status-msg err";
      statusBox.textContent = "Could not send your message right now. Please try again shortly.";
    }
  });
});
