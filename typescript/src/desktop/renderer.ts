const source = document.querySelector<HTMLTextAreaElement>('#source')!;
const output = document.querySelector<HTMLElement>('#output')!;
source.value = 'title=synthetic host spike; count=2; seed=1234,_; shift=(1.5,1.75)+0.05; aspect=1:1\nA [COLOR] circle on a plain background.\n%%FIELDS%%\nCOLOR={red|blue}';
async function show(action: () => Promise<unknown>): Promise<void> {
  try { const result = await action(); output.textContent = typeof result === 'string' ? result : JSON.stringify(result, null, 2); }
  catch (error) { output.textContent = String(error); }
}
document.querySelector('#preview')!.addEventListener('click', () => void show(() => window.storyBatch.preview(source.value)));
document.querySelector('#run')!.addEventListener('click', () => { output.textContent = 'Running synthetic jobs…'; void show(() => window.storyBatch.runFake(source.value)); });
document.querySelector('#cancel')!.addEventListener('click', () => void show(() => window.storyBatch.cancelFake().then(() => 'Cancellation requested.')));
document.querySelector('#probe')!.addEventListener('click', () => void show(() => window.storyBatch.probe()));
