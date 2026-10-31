import { Composition } from "remotion";
import { ParkDemo, TOTAL } from "./ParkDemo";
import { FPS, HEIGHT, WIDTH } from "./theme";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="ParkDemo" component={ParkDemo} durationInFrames={TOTAL} fps={FPS} width={WIDTH} height={HEIGHT} />
    </>
  );
};
