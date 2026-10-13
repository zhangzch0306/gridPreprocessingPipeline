% function to implement the manualFitGridROIs automatically

% --- Executes on button press in ok.

function fitGridROIs(datapath,roipath)

disp('loading files')

data=load_tiffs_fast(datapath);
rois=load(roipath);

% radius,FtoFcWindow,ROImasks,ROIs
% remains the same as the template file
output.ROImasks=rois.ROImasks;
output.radius=rois.radius;
output.FtoFcWindow=rois.FtoFcWindow;
output.ROIs=rois.ROIs;

% regenerate the snapshot,snapshotThreshold
output.snapshot=mean(double(data),3);
output.snapshotThresh = output.snapshot; 

% -- Executes the 'done' button 
disp('saving ROI data')
% get the timeseries and dF/F
[output.F,output.Fc,output.F_baseline,~] = getGridROITimeseries(output.ROImasks,data,output.FtoFcWindow);

% save out data and remove the template file
outputPath = [datapath(1:end-4) '_ROIs.mat'];
save(outputPath,'-struct','output');

end





