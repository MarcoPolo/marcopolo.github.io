FROM gitpod/workspace-full
                    
ENV TRIGGER_REBUILD 1

USER gitpod
RUN brew install zola
