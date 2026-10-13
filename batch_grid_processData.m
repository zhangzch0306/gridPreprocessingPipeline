% batch_grid_processData.m
% Mai-Anh Vu, updated 5/11/2020
%
% NOTE: This is is an example batch script for processing grid data (it
% calls grid_processData.m). You'll want to save your own version of this
% script, edited for your data.

% Last updated by Alice to include the internal_fitGridROI function, the
% function won't run if there's no small ROI template detected.

%%%%%%%%%%%%%%%%%%
%%% USER INPUT %%%
%%%%%%%%%%%%%%%%%%

%%%%% 1. assign a cell array to mouseList %%%%%
% this should be an nx2 cell array where n = the number of mice to process.
% Column 1 is the mouse's name (should be identical to directory name)
% Column 2 is the full path to a template .tif file 

dataDir = '\\RKC-HOW-WD-0006\AliceDrive5\iGlusnfr_data';
mouseList = {
    '869','\\RKC-HOW-WD-0006\AliceDrive5\iGlusnfr_data\869\260914\869_1dir_middle_405470_470_MC.tif';...
    '886','\\RKC-HOW-WD-0006\AliceDrive5\iGlusnfr_data\886\260923\886_GUI_405470_470_MC.tif';...
    '885','\\RKC-HOW-WD-0006\AliceDrive5\iGlusnfr_data\885\260923\885_GUI_405470_470_MC.tif';...
    '943','\\RKC-HOW-WD-0006\AliceDrive5\iGlusnfr_data\943\260914\943_1dir_middle_405470_470_MC.tif';...
    };

%%%%% 2. set some parameters %%%%%

% percent motion allowance 
motAllow = .12; %.12 = 12% = 12 pixels in ea direction if size is 100x100

% if you want to do this in order of newest recording day to oldest, vs if
% you want to do this one mouse (all the way through) at a time
% do this by date: 1 (vs. by mouse: 0);
byDate = 0;


%%%%%%%%%%%%%%%%%%%%%%%
%%% END: USER INPUT %%%
%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%
%%% OTHER SET UP %%%
%%%%%%%%%%%%%%%%%%%%

% turn off some warnings
warning('off','imageio:tiffmexutils:libtiffWarning')
warning('off','imageio:tiffmexutils:libtiffErrorAsWarning')
warning('off','imageio:tifftagsread:expectedTagDataFormatMultiple')
warning('off', 'MATLAB:imagesci:tiffmexutils:libtiffErrorAsWarning')
warning('off', 'imagesci:tiffmexutils:libtiffErrorAsWarning')
warning('off','MATLAB:polyshape:repairedBySimplify')

%%%%%%%%%%%%%%%%%
%%% MAIN LOOP %%%
%%%%%%%%%%%%%%%%%
if strcmp(mfilename,'batch_grid_processData.m')
    disp('You are currently using ')
    disp('batch_grid_processData.m.')
    disp('I recommend you save your')    
    disp('own version (with its own name)')
    disp('so you can tailor it to your needs.')
    disp('This one is likely to change.')
end

if byDate ==1
    % get date list if we're doing this by date
    dateList = [];
    for m = 1:size(mouseList,1) % loop over mice
        mouse = mouseList{m,1};        
        dates = dir([dataDir filesep mouse]);
        dates = {dates.name}';
        dates = dates(startsWith(dates,'25') | startsWith(dates,'26'));
        for d = 1:numel(dates)
            dateList{end+1} = dates{d};
        end
    end
    dateList = unique(dateList)';
    for d = numel(dateList):-1:1 % start with the most recent date
        date = dateList{d};
        % now loop over mice and see who has data for that date
        for m = 1:size(mouseList,1)
            mouse = mouseList{m,1};   
            templateFilepath = mouseList{m,2};
            dateDir = [dataDir filesep mouse filesep date filesep];
            if exist(dateDir,'dir') % if that mouse has data on this date
                disp('*****************')
                disp([mouse ' ' date])   
                % load this to save time                
                templateTif = load_tiffs_fast_v2(templateFilepath);
                %grid_processData(dateDir,'motAllow',motAllow);
                grid_processData_Alice(dateDir,'templateTif',templateTif,'motAllow',motAllow);
            end
        end
    end
else
    for m = 1:size(mouseList,1)
        mouse = mouseList{m,1};
        templateFilepath = mouseList{m,2};
        % load this to save time                
        templateTif = load_tiffs_fast_v2(templateFilepath);                        
        dates = dir([dataDir filesep mouse]);
        dates = {dates.name};
        dates = dates(startsWith(dates,'25') | startsWith(dates,'26'));
        for d = numel(dates):-1:1 % loop over dates, starting with most recent
            date = dates{d};
            dateDir = [dataDir filesep mouse filesep date filesep];
            disp('*****************')
            disp([mouse ' ' date])              
            %grid_processData(dateDir,'motAllow',motAllow);
            grid_processData_Alice(dateDir,'templateTif',templateTif,'motAllow',motAllow);
        end
    end
end


 

