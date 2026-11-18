/// Older native versions expose only `demo`; newer ones split media simulation
/// from vehicle simulation so high-fidelity mode always uses the real player.
bool mediaIsDemo(Map<String, dynamic> native) {
  if (native['mediaDemo'] is bool) return native['mediaDemo'] == true;
  if (native['simulationMode'] == 'highFidelity') return false;
  return native['demo'] == true;
}
